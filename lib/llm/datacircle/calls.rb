# frozen_string_literal: true

module LLM
  module Datacircle
    # A plan holds about 90 keys (its terms of use, its aggregators...): these choose a plan, the rest is on its page.
    PLAN_KEYS = ::Ractor.make_shareable(%w[api rank provider plan score perThousand notFoundPerThousand billing pay
                                           currency units unit strengths latencyMs page pricingPage docs])

    # The keys of an API on GET /apis the model gets.
    API_KEYS = ::Ractor.make_shareable(%w[api slug plans providers best bestPage sheetPage])

    # Tells a model that sent a provider's name to an API's tool where a provider's plans are.
    FOR_PROVIDER = "A provider's plans: datacircle-search-plans with its name as query, like bright data, " \
                   'or datacircle-provider.'

    # Tells a model that sent an API's slug to the provider's tool where an API's best providers are.
    FOR_API = "An API's best providers: datacircle-best-plans with the API's slug, like email-finder."

    # A placeholder a small model copies from a prompt's example, like <api-slug>, sent in place of a slug.
    PLACEHOLDER = /[<>{}]/

    # Accented Latin letters, lowercase, and the letter each is without its accent (Unicode's own decomposition): a
    # name's slug without String#unicode_normalize, whose tables a ractor can't read.
    ACCENTED = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿāăąćĉċčďēĕėęěĝğġģĥĩīĭįĵķĺļľńņňōŏőŕŗřś' \
               'ŝşšţťũūŭůűųŵŷźżžſơưǎǐǒǔǖǘǚǜǟǡǧǩǫǭǰǵǹǻȁȃȅȇȉȋȍȏȑȓȕȗșțȟȧȩȫȭȯȱȳḁḃḅḇḉ' \
               'ḋḍḏḑḓḕḗḙḛḝḟḡḣḥḧḩḫḭḯḱḳḵḷḹḻḽḿṁṃṅṇṉṋṍṏṑṓṕṗṙṛṝṟṡṣṥṧṩṫṭṯṱṳṵṷṹṻṽṿẁẃẅẇẉ' \
               'ẋẍẏẑẓẕẖẗẘẙẛạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ'
    UNACCENTED = 'aaaaaaceeeeiiiinooooouuuuyyaaaccccdeeeeegggghiiiijklllnnnooorrrs' \
                 'sssttuuuuuuwyzzzsouaiouuuuuaagkoojgnaaaeeiioorruusthaeooooyabbbc' \
                 'dddddeeeeefghhhhhiikkkllllmmmnnnnoooopprrrrsssssttttuuuuuvvwwwww' \
                 'xxyzzzhtwysaaaaaaaaaaaaeeeeeeeeiioooooooooooouuuuuuuyyyy'

    # The letters that are two without their accent, lowercase.
    LIGATURES = ::Ractor.make_shareable({ 'ĳ' => 'ij', 'ǆ' => 'dz', 'ǉ' => 'lj', 'ǌ' => 'nj', 'ǳ' => 'dz' })

    # The four calls of https://api.datacircle.dev/v1 behind the tools, each answering the Hash the model reads: an
    # answer of 4xx (an unknown slug, a wrong argument) as {"error" => the API's words}. Error is raised when the API
    # can't be reached or answers 5xx, and llm.rb gives it to the model as an in-band error.
    class Calls
      def initialize(base_url: Client::BASE)
        @client = Client.new(base_url: base_url)
      end

      # GET /apis, the APIs whose name or slug holds the most of the query's words first.
      def list_apis(query: nil, limit: nil)
        apis = objects(@client.get('/apis'))
        words = query.to_s.downcase.tr('-', ' ').split
        found = apis.each_with_index.filter_map do |api, order|
          name = "#{api['api']} #{api['slug'].to_s.tr('-', ' ')}".downcase
          matched = words.count { |word| name.include?(word) }
          [-matched, order, api] if matched.positive? || words.empty?
        end.sort_by { |matched, order, _| [matched, order] }
        answer = { 'total' => found.size,
                   'apis' => found.first(number(limit, 200) || 20).map { |_, _, api| brief(api, API_KEYS) } }
        if words.any? && (found.empty? || -found.first.first < words.size)
          # A provider's name sent as an API's, like Bright Data, whose data matches many APIs: where its plans are.
          answer['note'] = "No API's name holds every word of #{query.to_s.to_json}. #{FOR_PROVIDER}"
        end
        answer
      rescue Error => e
        refusal(e)
      end

      # GET /apis/{slug}/best
      def best_plans(slug: nil, limit: nil)
        if slug.to_s.match?(PLACEHOLDER)
          return { 'error' => "#{slug.to_s.to_json} is a placeholder. Give the API's own slug, like email-finder: " \
                              'datacircle-list-apis gives every slug.' }
        end
        api = slugify(slug)
        if api.empty?
          return { 'error' => "Give an API's slug, like email-finder: datacircle-list-apis gives every slug. #{FOR_PROVIDER}" }
        end

        begin
          best(api, limit)
        rescue Error => e
          return refusal(e) unless e.status == 404

          # The slug with "api" after it, like serp-api, as the sheet's address reads (/serp-api-pricing): the API's own.
          bare = api.sub(/-api(-pricing)?\z/, '')
          if bare != api && !bare.empty?
            begin
              return best(bare, limit).merge('note' => "No API has the slug #{api}: these are #{bare}'s plans.")
            rescue Error
              # The first answer stands.
            end
          end
          # An API's name sent as its slug, like Employee email: the API of that name.
          named = objects(@client.get('/apis')).find { |entry| slugify(entry['api']) == api }
          return best(named['slug'], limit) if named

          # A provider's name sent as the API's slug: the API's words, and where a provider's plans are.
          { 'error' => "#{e.message}. datacircle-list-apis gives every API's slug. #{FOR_PROVIDER}" }
        end
      rescue Error => e
        refusal(e)
      end

      # GET /plans
      def search_plans(api: nil, query: nil, sort: nil, limit: nil, offset: nil)
        api = api.to_s
        query = query.to_s
        sort = sort.to_s.strip.downcase
        notes = []
        search = lambda do |on, words|
          @client.get('/plans', api: on.strip, query: words.strip, sort: (sort if %w[score provider price].include?(sort)),
                                limit: number(limit, 50), offset: number(offset, 1_000_000, low: 0))
        end
        begin
          answer = search.call(api, query)
        rescue Error => e
          raise unless e.status == 400 && e.message.include?('api must be') && query.strip.empty?

          # A provider's name sent as the API: the plans whose provider or plan name holds it.
          notes << "No API is named #{api.to_json}: these are the plans whose provider or plan name holds it."
          api, query = '', api
          answer = search.call(api, query)
        end
        if answer['total'].to_i.zero? && query.include?('-')
          # A slug sent as a name, like bright-data, which no name holds: its words, like bright data. A name with a
          # hyphen, like A-Leads, is found as it is first.
          words = query.tr('-', ' ').split.join(' ')
          begin
            answer = search.call(api, words)
            notes << "No provider's or plan's name holds #{query.to_json}: these are the plans whose name holds #{words.to_json}."
          rescue Error
            # The first answer stands.
          end
        end
        answer = answer.merge('plans' => objects(answer['plans']).map { |plan| brief(plan) })
        notes.empty? ? answer : answer.merge('note' => notes.join(' '))
      rescue Error => e
        refusal(e)
      end

      # GET /providers/{slug}
      def provider(slug: nil)
        if slug.to_s.match?(PLACEHOLDER)
          return { 'error' => "#{slug.to_s.to_json} is a placeholder. Give the provider's own slug or name, like " \
                              'bright-data or Bright Data.' }
        end
        name = slugify(slug)
        return { 'error' => "Give a provider's slug or name, like bright-data or Bright Data" } if name.empty?

        begin
          answer = @client.get("/providers/#{name}")
        rescue Error => e
          # An API's slug sent as a provider's, like email-finder: the API's words, and where an API's best providers are.
          return e.status == 404 ? { 'error' => "#{e.message}. #{FOR_API}" } : refusal(e)
        end
        apis = objects(answer['apis']).map do |entry|
          plans = objects(entry['plans'])
          kept = brief(entry, %w[api slug rank bestPage]).merge('plans' => plans.size)
          top = best_plan(plans)
          top ? kept.merge('best' => brief(top, %w[plan score perThousand page])) : kept
        end
        # Its best rank first, the APIs where it has none last, in the API's order.
        apis = apis.each_with_index.sort_by { |entry, order| [entry['rank'].is_a?(::Numeric) ? entry['rank'] : ::Float::INFINITY, order] }
                   .map(&:first)
        answer.merge('apis' => apis, 'total' => apis.size, 'ranked' => apis.count { |entry| entry['rank'].is_a?(::Numeric) })
      end

      private

      def best(api, limit)
        answer = @client.get("/apis/#{api}/best", limit: number(limit, 50))
        answer.merge('plans' => objects(answer['plans']).map { |plan| brief(plan) })
      end

      # An answer of 4xx as the model reads it, the API's words; anything else raised.
      def refusal(error)
        raise error unless error.status && error.status >= 400 && error.status < 500

        { 'error' => error.message }
      end

      def brief(item, keys = PLAN_KEYS)
        keys.each_with_object({}) { |key, kept| kept[key] = item[key] unless item[key].nil? }
      end

      def objects(value)
        value.is_a?(::Array) ? value.select { |item| item.is_a?(::Hash) } : []
      end

      # A number the model sent, as a number or as its digits, within the API's bounds: nil for the API's default.
      def number(value, high, low: 1)
        given = value.is_a?(::Numeric) ? value.to_i : ::Kernel.Integer(value.to_s.strip, 10)
        given < low ? nil : given.clamp(low, high)
      rescue ::ArgumentError, ::TypeError, ::FloatDomainError
        nil
      end

      # The API's rule for a slug: the name in lowercase letters and digits, the rest a hyphen.
      def slugify(value)
        value.to_s.downcase.tr(ACCENTED, UNACCENTED).gsub(/[ĳǆǉǌǳ]/, LIGATURES).gsub(/\p{Mn}/, '')
             .gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
      end

      # A provider's best plan on an API: its lowest rank, the first when none has a rank.
      def best_plan(plans)
        plans.select { |plan| plan['rank'].is_a?(::Numeric) }.min_by { |plan| plan['rank'] } || plans.first
      end
    end
  end
end
