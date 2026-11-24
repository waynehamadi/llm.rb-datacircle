# frozen_string_literal: true

module LLM
  module Datacircle
    PRICE = "perThousand is a plan's price of 1,000 items in dollars, pay the plan's whole price in its currency."

    # GET /apis
    class ListApis < LLM::Tool
      name 'datacircle-list-apis'
      description "Lists the GTM APIs on Datacircle's sheet (https://datacircle.dev). GTM means go-to-market. GTM " \
                  "APIs are the APIs sales and marketing teams use. Gives each API's slug, how many plans and " \
                  "providers it has and its best plan. Call it first to find an API's slug."
      parameter :query, String, "Words of the API's name or slug, like email or linkedin profile: the APIs that hold " \
                                "the most of them come first. Left out, the sheet's order"
      parameter :limit, Integer, 'How many APIs to give, 1 to 200. 20 when left out: the sheet has about 150'

      def call(query: nil, limit: nil, **)
        Calls.new.list_apis(query: query, limit: limit)
      end
    end

    # GET /apis/{slug}/best
    class BestPlans < LLM::Tool
      name 'datacircle-best-plans'
      description "Gives an API's plans best first by their score out of 100 on Datacircle's benchmark " \
                  '(https://datacircle.dev), each with its rank, provider, plan, $ per 1,000 calls and its page. ' \
                  "#{PRICE}"
      parameter :slug, String, "The API's slug, like email-finder or linkedin-profile, as datacircle-list-apis gives it"
      parameter :limit, Integer, 'How many plans to give, 1 to 50. 10 when left out'
      required %i[slug]

      def call(slug: nil, limit: nil, **)
        Calls.new.best_plans(slug: slug, limit: limit)
      end
    end

    # GET /plans
    class SearchPlans < LLM::Tool
      name 'datacircle-search-plans'
      description "Searches every plan on Datacircle's sheet (https://datacircle.dev), or one API's, by provider or " \
                  'plan name, sorted by score, provider or price. Gives how many were found and up to limit of them. ' \
                  "#{PRICE}"
      parameter :api, String, "Only this API's plans: its name or slug, like email-finder. A provider's name goes in " \
                              'query, never here. Left out, every API'
      parameter :query, String, "Words that must all appear in the provider's or plan's name, like bright data. Left " \
                                'out, every plan'
      parameter :sort, Enum['score', 'provider', 'price'],
                'score (best first, the default), provider (A to Z) or price ($ per 1,000, lowest first)'
      parameter :limit, Integer, 'How many plans to give, 1 to 50. 10 when left out'
      parameter :offset, Integer, 'How many found plans to skip first. 0 when left out'

      def call(api: nil, query: nil, sort: nil, limit: nil, offset: nil, **)
        Calls.new.search_plans(api: api, query: query, sort: sort, limit: limit, offset: offset)
      end
    end

    # GET /providers/{slug}
    class Provider < LLM::Tool
      name 'datacircle-provider'
      description "Gives each API one provider sells and its rank on each on Datacircle's benchmark " \
                  '(https://datacircle.dev), with its best plan there, its best rank first. total is how many APIs ' \
                  "it sells, ranked on how many of them it has a rank. For an API's best providers, call " \
                  'datacircle-best-plans.'
      parameter :slug, String, "The provider's slug, like bright-data, or its name, like Bright Data: the name is " \
                               'made a slug'
      required %i[slug]

      def call(slug: nil, **)
        Calls.new.provider(slug: slug)
      end
    end
  end
end
