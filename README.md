# Jenkins-Murray

This repo contains bones for quick installation and setup of a CI/CD environment with **Fastlane** and **Jenkins**.

## Installation 

### Using Murray:

- If you already have a `Gemfile`, add `#MURRAY PLACEHOLDER` at the end of it.
- Add `git@github.com:stefanomondino/Jenkins-Murray.git@master` to your `remoteBones` array in your `Skeletonspec.json`
- run `murray bone setup` to clone it
- run `murray bone new jenkins empty` (you can use `empty` or whatever placeholder you need, it's not used in this case)
- run `bundle install --path vendor/bundle`

### Without Murray:

- Clone this repo in your main root
- Add this script at the end of your Gemfile:

```ruby
plugins_path = File.join(File.dirname(__FILE__), 'fastlane', 'Pluginfile')
eval_gemfile(plugins_path) if File.exist?(plugins_path)
```
- run `bundle install --path vendor/bundle`


## Usage

//TODO
