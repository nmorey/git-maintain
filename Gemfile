# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

if (RUBY_VERSION < '2.7.0')
    gem 'octokit', '>= 3.0', '< 5'
else
    gem 'octokit', '~> 5.0'
end
