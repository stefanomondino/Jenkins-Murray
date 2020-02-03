pipeline {
    //labels for jenkins agents
    //use agent any if Jenkins has a single node
    agent { label 'ios && pipeline' }
    
    options {
        ansiColor("xterm")
    }
    
    parameters {
        booleanParam (
            defaultValue: false,
            description: 'Create screenshots',
            name : 'SCREENSHOTS')

         booleanParam (
            defaultValue: true,
            description: 'Compile and distribute enterprise',
            name : 'ENTERPRISE')

        booleanParam (
            defaultValue: false,
            description: 'Compile and distribute appstore',
            name : 'APPSTORE')
        text (
            name: 'RELEASE_NOTES',
            defaultValue: 'Released with Fastlane and Jenkins',
            description: 'Release notes for beta distribution')
    }
    
    environment {
        MATCH_KEYCHAIN_NAME = "${env.KEYCHAIN_NAME}"
        MATCH_KEYCHAIN_PASSWORD = "${env.SYSTEM_KEYCHAIN_PASSWORD}"
        MATCH_PASSWORD = "${env.SYN_MATCH_PASSWORD}"
        JOB_NAME = "${env.JOB_BASE_NAME}"
        SLACK_URL = "${env.SLACK_IOS_URL}"
        RELEASE_NOTES = "${params.RELEASE_NOTES}"
    }
    stages {
        stage("Init") {
            steps {
                
                bash "bundle install"
                bash "bundle exec fastlane project_setup"
            }
        }
        
        stage("Screenshots") {
            
            environment {
                ENVIRONMENT = "appstore"
            }
            
            when {
                expression {
                    return params.SCREENSHOTS
                }
            }
            
            steps {
                script {
                    bash "bundle exec fastlane screenshots"
                    bash "bundle exec fastlane upload_screenshots"
                }
            }
        }
        
        stage("Build and deploy to Firebase") {
            environment {
                  ENVIRONMENT = "enterprise"
              }
            when {
                expression {
                    return params.ENTERPRISE
                }
            }
            steps {
                script {
                  bash "bundle exec fastlane build_application"
                }
            }
        }
        
        stage("Build and deploy to Appstore") {
            environment {
                  ENVIRONMENT = "appstore"
              }
              when {
                expression {
                    return params.APPSTORE
                }
            }
            steps {
                script {
                  bash "bundle exec fastlane build_application"
                }
            }
        }
        
    }
    post {
        failure {
            updateGitlabCommitStatus name: 'build', state: 'failed'
        }
        success {
            updateGitlabCommitStatus name: 'build', state: 'success'
        }
    }
}

def bash(custom) {
    sh '''#!/bin/bash -l
    export LANG=en_US.UTF-8
    export LANGUAGE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    ''' + custom
    
}
