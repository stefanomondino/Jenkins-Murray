require "match/options"
require "match/runner"
require "match/nuke"
require "match/utils"
require "match/table_printer"
require "match/generator"
require "match/setup"
require "match/spaceship_ensure"
require "match/change_password"
require "match/migrate"
require "match/importer"
require "match/storage"
require "match/encryption"
require "match/module"
require "spaceship"
require "fileutils"

module Fastlane
  module Actions
    module SharedValues
      CUSTOM_IMPORT_CUSTOM_VALUE = :CUSTOM_IMPORT_CUSTOM_VALUE
    end

    class CustomImportAction < Action
      def self.run(params)
        # fastlane will take care of reading in the parameter and fetching the environment variable:
        #        UI.message "Parameter API Token: #{params[:api_token]}"
        cert_path = params[:cert_path]
        p12_path = params[:p12_path]
        profile_path = params[:profile_path]
        matching_cert_id = params[:matching_cert_id]
        # Get and verify cert and p12 path
        cert_path ||= UI.input("Certificate (.cer) path:")
        p12_path ||= UI.input("Private key (.p12) path:")
        profile_path ||= UI.input("Provisioning Profile (.mobileprovision) path:")
        matching_cert_id ||= UI.input("Certificate id:")
        cert_path = File.absolute_path(cert_path)
        p12_path = File.absolute_path(p12_path)
        profile_path = File.absolute_path(profile_path)

        UI.user_error!("Certificate does not exist at path: #{cert_path}") unless File.exist?(cert_path)
        UI.user_error!("Private key does not exist at path: #{p12_path}") unless File.exist?(p12_path)
        UI.user_error!("Provisioning profile does not exist at path: #{profile_path}") unless File.exist?(profile_path)
        # Base64 encode contents to find match from API to find a cert ID
        cert_contents_base_64 = Base64.strict_encode64(File.open(cert_path).read)

        # Storage
        storage = Match::Storage.for_mode(params[:storage_mode], {
          git_url: params[:git_url],
          shallow_clone: params[:shallow_clone],
          skip_docs: params[:skip_docs],
          git_branch: params[:git_branch],
          git_full_name: params[:git_full_name],
          git_user_email: params[:git_user_email],
          clone_branch_directly: params[:clone_branch_directly],
          type: params[:type].to_s,
          platform: params[:platform].to_s,
          google_cloud_bucket_name: params[:google_cloud_bucket_name].to_s,
          google_cloud_keys_file: params[:google_cloud_keys_file].to_s,
          google_cloud_project_id: params[:google_cloud_project_id].to_s,
          readonly: params[:readonly],
          username: params[:username],
          team_id: params[:team_id],
          team_name: params[:team_name],
        })
        storage.download

        # Encryption
        encryption = Match::Encryption.for_storage_mode(params[:storage_mode], {
          git_url: params[:git_url],
          working_directory: storage.working_directory,
        })
        encryption.decrypt_files if encryption
        UI.success("Repo is at: '#{storage.working_directory}'")

        # Map match type into Spaceship::ConnectAPI::Certificate::CertificateType
        cert_type = Match.cert_type_sym(params[:type])

        case cert_type
        when :development
          certificate_type = Spaceship::ConnectAPI::Certificate::CertificateType::IOS_DEVELOPMENT + "," + Spaceship::ConnectAPI::Certificate::CertificateType::DEVELOPMENT
        when :distribution, :enterprise
          certificate_type = Spaceship::ConnectAPI::Certificate::CertificateType::IOS_DISTRIBUTION + "," + Spaceship::ConnectAPI::Certificate::CertificateType::DISTRIBUTION
        else
          UI.user_error!("Cert type '#{cert_type}' is not supported")
        end

        output_dir = File.join(storage.prefixed_working_directory, "certs", cert_type.to_s)

        # Make dir if doesn't exist
        FileUtils.mkdir_p(output_dir)
        dest_cert_path = File.join(output_dir, "#{matching_cert_id}.cer")
        dest_p12_path = File.join(output_dir, "#{matching_cert_id}.p12")

        output_dir = File.join(storage.prefixed_working_directory, "profiles", params[:type].to_s)
        dest_profile_path = File.join(output_dir, "#{profile_type_name(params[:type].to_s)}_#{params[:app_identifier].first.to_s}.mobileprovision")

        # Copy files
        IO.copy_stream(cert_path, dest_cert_path)
        IO.copy_stream(p12_path, dest_p12_path)
        IO.copy_stream(profile_path, dest_profile_path)
        files_to_commit = [dest_cert_path, dest_p12_path, dest_profile_path]

        # Encrypt and commit
        encryption.encrypt_files if encryption
        storage.save_changes!(files_to_commit: files_to_commit)
      end

      def self.profile_type_name(type)
        return "Direct" if type == :developer_id
        return "Development" if type == :development
        return "AdHoc" if type == :adhoc || type == "adhoc"
        return "AppStore" if type == :appstore || type == "appstore"
        return "InHouse" if type == :enterprise || type == "enterprise"
        return "Unknown"
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "A short description with <= 80 characters of what this action does"
      end

      def self.details
        # Optional:
        # this is your chance to provide a more detailed description of this action
        "You can use this action to do cool things..."
      end
      def self.available_options
        user = CredentialsManager::AppfileConfig.try_fetch_value(:apple_dev_portal_id)
        user ||= CredentialsManager::AppfileConfig.try_fetch_value(:apple_id)

        [
          # main
          FastlaneCore::ConfigItem.new(key: :type,
                                       env_name: "MATCH_TYPE",
                                       description: "Define the profile type, can be #{Match.environments.join(", ")}",
                                       short_option: "-y",
                                       default_value: "development",
                                       verify_block: proc do |value|
                                         unless Match.environments.include?(value)
                                           UI.user_error!("Unsupported environment #{value}, must be in #{Match.environments.join(", ")}")
                                         end
                                       end),
          FastlaneCore::ConfigItem.new(key: :additional_cert_types,
                                       env_name: "MATCH_ADDITIONAL_CERT_TYPES",
                                       description: "Create additional cert types needed for macOS installers (valid values: mac_installer_distribution, developer_id_installer)",
                                       optional: true,
                                       type: Array,
                                       verify_block: proc do |values|
                                         types = %w(mac_installer_distribution developer_id_installer)
                                         UI.user_error!("Unsupported types, must be: #{types}") unless (values - types).empty?
                                       end),
          FastlaneCore::ConfigItem.new(key: :readonly,
                                       env_name: "MATCH_READONLY",
                                       description: "Only fetch existing certificates and profiles, don't generate new ones",
                                       type: Boolean,
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :generate_apple_certs,
                                       env_name: "MATCH_GENERATE_APPLE_CERTS",
                                       description: "Create a certificate type for Xcode 11 and later (Apple Development or Apple Distribution)",
                                       type: Boolean,
                                       default_value: FastlaneCore::Helper.mac? && FastlaneCore::Helper.xcode_at_least?("11"),
                                       default_value_dynamic: true),
          FastlaneCore::ConfigItem.new(key: :skip_provisioning_profiles,
                                       env_name: "MATCH_SKIP_PROVISIONING_PROFILES",
                                       description: "Skip syncing provisioning profiles",
                                       type: Boolean,
                                       default_value: false),

          # app
          FastlaneCore::ConfigItem.new(key: :app_identifier,
                                       short_option: "-a",
                                       env_name: "MATCH_APP_IDENTIFIER",
                                       description: "The bundle identifier(s) of your app (comma-separated)",
                                       type: Array, # we actually allow String and Array here
                                       skip_type_validation: true,
                                       code_gen_sensitive: true,
                                       default_value: CredentialsManager::AppfileConfig.try_fetch_value(:app_identifier),
                                       default_value_dynamic: true),
          FastlaneCore::ConfigItem.new(key: :username,
                                       short_option: "-u",
                                       env_name: "MATCH_USERNAME",
                                       description: "Your Apple ID Username",
                                       default_value: user,
                                       default_value_dynamic: true),
          FastlaneCore::ConfigItem.new(key: :team_id,
                                       short_option: "-b",
                                       env_name: "FASTLANE_TEAM_ID",
                                       description: "The ID of your Developer Portal team if you're in multiple teams",
                                       optional: true,
                                       code_gen_sensitive: true,
                                       default_value: CredentialsManager::AppfileConfig.try_fetch_value(:team_id),
                                       default_value_dynamic: true),
          FastlaneCore::ConfigItem.new(key: :team_name,
                                       short_option: "-l",
                                       env_name: "FASTLANE_TEAM_NAME",
                                       description: "The name of your Developer Portal team if you're in multiple teams",
                                       optional: true,
                                       code_gen_sensitive: true,
                                       default_value: CredentialsManager::AppfileConfig.try_fetch_value(:team_name),
                                       default_value_dynamic: true),

          # Storage
          FastlaneCore::ConfigItem.new(key: :storage_mode,
                                       env_name: "MATCH_STORAGE_MODE",
                                       description: "Define where you want to store your certificates",
                                       short_option: "-q",
                                       default_value: "git",
                                       verify_block: proc do |value|
                                         unless Match.storage_modes.include?(value)
                                           UI.user_error!("Unsupported storage_mode #{value}, must be in #{Match.storage_modes.join(", ")}")
                                         end
                                       end),

          # Storage: Git
          FastlaneCore::ConfigItem.new(key: :git_url,
                                       env_name: "MATCH_GIT_URL",
                                       description: "URL to the git repo containing all the certificates",
                                       optional: false,
                                       short_option: "-r"),
          FastlaneCore::ConfigItem.new(key: :git_branch,
                                       env_name: "MATCH_GIT_BRANCH",
                                       description: "Specific git branch to use",
                                       default_value: "master"),
          FastlaneCore::ConfigItem.new(key: :git_full_name,
                                       env_name: "MATCH_GIT_FULL_NAME",
                                       description: "git user full name to commit",
                                       optional: true,
                                       default_value: nil),
          FastlaneCore::ConfigItem.new(key: :git_user_email,
                                       env_name: "MATCH_GIT_USER_EMAIL",
                                       description: "git user email to commit",
                                       optional: true,
                                       default_value: nil),
          FastlaneCore::ConfigItem.new(key: :shallow_clone,
                                       env_name: "MATCH_SHALLOW_CLONE",
                                       description: "Make a shallow clone of the repository (truncate the history to 1 revision)",
                                       type: Boolean,
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :clone_branch_directly,
                                       env_name: "MATCH_CLONE_BRANCH_DIRECTLY",
                                       description: "Clone just the branch specified, instead of the whole repo. This requires that the branch already exists. Otherwise the command will fail",
                                       type: Boolean,
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :git_basic_authorization,
                                       env_name: "MATCH_GIT_BASIC_AUTHORIZATION",
                                       sensitive: true,
                                       description: "Use a basic authorization header to access the git repo (e.g.: access via HTTPS, GitHub Actions, etc), usually a string in Base64",
                                       conflicting_options: [:git_bearer_authorization],
                                       optional: true,
                                       default_value: nil),
          FastlaneCore::ConfigItem.new(key: :git_bearer_authorization,
                                       env_name: "MATCH_GIT_BEARER_AUTHORIZATION",
                                       sensitive: true,
                                       description: "Use a bearer authorization header to access the git repo (e.g.: access to an Azure Devops repository), usually a string in Base64",
                                       conflicting_options: [:git_basic_authorization],
                                       optional: true,
                                       default_value: nil),

          # Storage: Google Cloud
          FastlaneCore::ConfigItem.new(key: :google_cloud_bucket_name,
                                       env_name: "MATCH_GOOGLE_CLOUD_BUCKET_NAME",
                                       description: "Name of the Google Cloud Storage bucket to use",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :google_cloud_keys_file,
                                       env_name: "MATCH_GOOGLE_CLOUD_KEYS_FILE",
                                       description: "Path to the gc_keys.json file",
                                       optional: true,
                                       verify_block: proc do |value|
                                         UI.user_error!("Could not find keys file at path '#{File.expand_path(value)}'") unless File.exist?(value)
                                       end),
          FastlaneCore::ConfigItem.new(key: :google_cloud_project_id,
                                       env_name: "MATCH_GOOGLE_CLOUD_PROJECT_ID",
                                       description: "ID of the Google Cloud project to use for authentication",
                                       optional: true),

          # Storage: S3
          FastlaneCore::ConfigItem.new(key: :s3_region,
                                       env_name: "MATCH_S3_REGION",
                                       description: "Name of the S3 region",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :s3_access_key,
                                       env_name: "MATCH_S3_ACCESS_KEY",
                                       description: "S3 access key",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :s3_secret_access_key,
                                       env_name: "MATCH_S3_SECRET_ACCESS_KEY",
                                       description: "S3 secret secret access key",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :s3_bucket,
                                       env_name: "MATCH_S3_BUCKET",
                                       description: "Name of the S3 bucket",
                                       optional: true),

          # Keychain
          FastlaneCore::ConfigItem.new(key: :keychain_name,
                                       short_option: "-s",
                                       env_name: "MATCH_KEYCHAIN_NAME",
                                       description: "Keychain the items should be imported to",
                                       default_value: "login.keychain"),
          FastlaneCore::ConfigItem.new(key: :keychain_password,
                                       short_option: "-p",
                                       env_name: "MATCH_KEYCHAIN_PASSWORD",
                                       sensitive: true,
                                       description: "This might be required the first time you access certificates on a new mac. For the login/default keychain this is your account password",
                                       optional: true),

          # settings
          FastlaneCore::ConfigItem.new(key: :force,
                                       env_name: "MATCH_FORCE",
                                       description: "Renew the provisioning profiles every time you run match",
                                       type: Boolean,
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :force_for_new_devices,
                                       env_name: "MATCH_FORCE_FOR_NEW_DEVICES",
                                       description: "Renew the provisioning profiles if the device count on the developer portal has changed. Ignored for profile type 'appstore'",
                                       type: Boolean,
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :skip_confirmation,
                                       env_name: "MATCH_SKIP_CONFIRMATION",
                                       description: "Disables confirmation prompts during nuke, answering them with yes",
                                       type: Boolean,
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :skip_docs,
                                       env_name: "MATCH_SKIP_DOCS",
                                       description: "Skip generation of a README.md for the created git repository",
                                       type: Boolean,
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :platform,
                                       short_option: "-o",
                                       env_name: "MATCH_PLATFORM",
                                       description: "Set the provisioning profile's platform to work with (i.e. ios, tvos, macos)",
                                       default_value: "ios",
                                       verify_block: proc do |value|
                                         value = value.to_s
                                         pt = %w(tvos ios macos)
                                         UI.user_error!("Unsupported platform, must be: #{pt}") unless pt.include?(value)
                                       end),
          FastlaneCore::ConfigItem.new(key: :template_name,
                                       env_name: "MATCH_PROVISIONING_PROFILE_TEMPLATE_NAME",
                                       description: "The name of provisioning profile template. If the developer account has provisioning profile templates (aka: custom entitlements), the template name can be found by inspecting the Entitlements drop-down while creating/editing a provisioning profile (e.g. \"Apple Pay Pass Suppression Development\")",
                                       optional: true,
                                       default_value: nil),
          FastlaneCore::ConfigItem.new(key: :output_path,
                                       env_name: "MATCH_OUTPUT_PATH",
                                       description: "Path in which to export certificates, key and profile",
                                       optional: true),

          # other
          FastlaneCore::ConfigItem.new(key: :verbose,
                                       env_name: "MATCH_VERBOSE",
                                       description: "Print out extra information and all commands",
                                       type: Boolean,
                                       default_value: false,
                                       verify_block: proc do |value|
                                         FastlaneCore::Globals.verbose = true if value
                                       end),

          # other
          FastlaneCore::ConfigItem.new(key: :cert_path,
                                       env_name: "CERT_PATH",
                                       description: "Print out extra information and all commands",
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :p12_path,
                                       env_name: "P12_PATH",
                                       description: "Print out extra information and all commands",
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :profile_path,
                                       env_name: "PROFILE_PATH",
                                       description: "Print out extra information and all commands",
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :matching_cert_id,
                                       env_name: "MATCHING_CERT_ID",
                                       description: "Print out extra information and all commands",
                                       default_value: false),
        ]
      end

      def self.output
      end

      def self.return_value
        # If your method provides a return value, you can describe here what it does
      end

      def self.authors
        # So no one will ever forget your contribution to fastlane :) You are awesome btw!
        ["stefanomondino"]
      end

      def self.is_supported?(platform)
        # you can do things like
        #
        #  true
        #
        #  platform == :ios
        #
        #  [:ios, :mac].include?(platform)
        #
        return true
        #platform == :ios
      end
    end
  end
end
