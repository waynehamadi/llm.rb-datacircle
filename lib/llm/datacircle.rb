# frozen_string_literal: true

require 'llm'
require_relative 'datacircle/version'
require_relative 'datacircle/client'
require_relative 'datacircle/calls'
require_relative 'datacircle/tools'

module LLM
  # Four llm.rb tools on Datacircle's open API (https://api.datacircle.dev/v1), with no key.
  module Datacircle
    # The four tools, for LLM::Agent.new(llm, tools: LLM::Datacircle.tools).
    def self.tools
      [ListApis, BestPlans, SearchPlans, Provider]
    end
  end
end
