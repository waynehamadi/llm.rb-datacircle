# frozen_string_literal: true

require_relative 'lib/llm/datacircle/version'

Gem::Specification.new do |spec|
  spec.name          = 'llm.rb-datacircle'
  spec.version       = LLM::Datacircle::VERSION
  spec.authors       = ['Wayne Hamadi']
  spec.email         = ['wayne@datacircle.dev']

  spec.summary       = 'Find the best GTM APIs, in llm.rb.'
  spec.description   = "Four llm.rb tools on Datacircle's open API, with no key: list the GTM APIs, the best plans of " \
                       "one API, a search of every plan and one provider's ranks. We benchmark all the GTM APIs and " \
                       'we put the results on our website: https://datacircle.dev'
  spec.homepage      = 'https://datacircle.dev'
  spec.license       = 'MIT'
  spec.metadata      = {
    'homepage_uri' => 'https://datacircle.dev',
    'source_code_uri' => 'https://github.com/waynehamadi/llm.rb-datacircle',
    'documentation_uri' => 'https://github.com/waynehamadi/llm.rb-datacircle#readme',
    'bug_tracker_uri' => 'https://github.com/waynehamadi/llm.rb-datacircle/issues'
  }

  spec.files         = Dir['LICENSE.txt', 'README.md', 'lib/**/*.rb']
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 3.4'

  spec.add_dependency 'llm.rb', '>= 16.0'
end
