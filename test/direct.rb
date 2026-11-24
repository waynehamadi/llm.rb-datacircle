# frozen_string_literal: true

# Each tool called live on https://api.datacircle.dev/v1 by its own call, as llm.rb's runtime calls it (symbol keys),
# and by llm.rb's own LLM::Function with the arguments a model sends (string keys, in an LLM::Object), with no model.
require 'llm/datacircle'

D = LLM::Datacircle
puts "llm.rb #{LLM::VERSION}, llm.rb-datacircle #{D::VERSION} " \
     "(#{$LOADED_FEATURES.grep(%r{llm/datacircle/version}).first}), Ruby #{RUBY_VERSION}"
failed = 0
check = lambda do |name, ok, shown = ''|
  puts "#{ok ? 'OK  ' : 'FAIL'} #{name}#{shown.to_s.empty? ? '' : ": #{shown.to_s[0, 220]}"}"
  failed += 1 unless ok
end

names = %w[datacircle-list-apis datacircle-best-plans datacircle-search-plans datacircle-provider]
check.call('four tools, named', D.tools.map(&:name) == names, D.tools.map(&:name).inspect)
check.call('each in llm.rb\'s registry', names.all? { |n| LLM::Tool.find_by_name(n) }, LLM::Tool.registry.size)
schemas = D.tools.map { |t| LLM.json.load(LLM.json.dump(t.function.params.to_h)) }
check.call('objects, required only where needed', schemas.all? { _1['type'] == 'object' } &&
           schemas.map { Array(_1['required']) } == [[], ['slug'], [], ['slug']], schemas.map { _1['required'] }.inspect)
check.call('sort an enum', schemas[2]['properties']['sort']['enum'] == %w[score provider price], schemas[2]['properties']['sort'])
check.call('limit an integer', schemas.values_at(0, 1, 2).all? { _1['properties']['limit']['type'] == 'integer' })

a = D::ListApis.new.call(query: 'email finder', limit: 3)
check.call('list_apis', a['apis'].size == 3 && a['apis'][0]['slug'] == 'email-finder' && a['total'] > 3, a['apis'].map { _1['slug'] }.inspect)
a = D::ListApis.new.call
check.call('list_apis no input', a['apis'].size == 20 && a['total'] > 100, a['total'])
a = D::ListApis.new.call(query: 'Bright Data')
check.call('list_apis a provider sent as its query: a note', a['note'].to_s.include?('datacircle-search-plans'), a['note'])
a = D::BestPlans.new.call(slug: 'email-finder', limit: 3)
check.call('best_plans', a['plans'].size == 3 && a['plans'][0]['rank'] == 1 && a['plans'][0].key?('perThousand'), a['plans'][0].slice('provider', 'plan', 'perThousand'))
check.call('best_plans keeps a plan brief', a['plans'][0].keys.all? { D::PLAN_KEYS.include?(_1) }, a['plans'][0].keys.inspect)
a = D::BestPlans.new.call(slug: 'Employee email', limit: 1.9)
check.call('best_plans an API name as slug, a fraction cut', a['slug'] == 'email-finder' && a['plans'].size == 1, a.slice('api', 'slug'))
a = D::BestPlans.new.call(slug: 'serp-api', limit: '2')
check.call('best_plans serp-api, a limit as text', a['slug'] == 'serp' && a['note'].to_s.include?('serp-api') && a['plans'].size == 2, a['note'])
a = D::BestPlans.new.call(slug: 'bright-data')
check.call('best_plans a provider as slug', a['error'].to_s.include?('datacircle-search-plans with its name'), a['error'])
a = D::BestPlans.new.call(slug: '<api-slug>')
check.call('best_plans a placeholder', a['error'].to_s.include?('placeholder'), a['error'])
a = D::BestPlans.new.call(slug: 'email-finder', limit: 500)
check.call('best_plans limit brought to 50', a['plans'].size == 50, a['plans'].size)
a = D::BestPlans.new.call
check.call('best_plans no slug', a['error'].to_s.start_with?("Give an API's slug"), a['error'])
a = D::SearchPlans.new.call(query: 'bright data', sort: 'price', limit: 3)
check.call('search_plans', a['total'] > 3 && a['plans'].size == 3 && a['plans'].all? { _1['provider'] == 'Bright Data' }, a['plans'].map { _1['perThousand'] }.inspect)
a = D::SearchPlans.new.call(api: 'email-finder', sort: 'price', limit: 2, offset: 2)
check.call('search_plans one API, offset', a['plans'].size == 2 && a['offset'] == 2, a.slice('total', 'offset'))
a = D::SearchPlans.new.call(api: 'Bright Data')
check.call('search_plans a provider sent as the API', a['note'].to_s.include?('No API is named') && a['plans'].all? { _1['provider'] == 'Bright Data' }, a['note'])
a = D::SearchPlans.new.call(query: 'bright-data', limit: 1)
check.call('search_plans a slug as its query', a['note'].to_s.include?('"bright data"') && a['plans'][0]['provider'] == 'Bright Data', a['note'])
a = D::SearchPlans.new.call(sort: 'cheapest', limit: 1)
check.call('search_plans a sort it lacks: the default', a['plans'].size == 1 && a['plans'][0]['rank'] == 1, a['plans'][0]&.slice('api', 'rank'))
a = D::SearchPlans.new.call(api: 'nothing-like-it')
check.call("search_plans an unknown API: the API's words", a['error'].to_s.include?('api must be') || a.key?('note'), a['error'] || a['note'])
a = D::Provider.new.call(slug: 'Bright Data')
check.call('provider by name', a['slug'] == 'bright-data' && a['total'] == a['apis'].size && a['ranked'] <= a['total'] && a['apis'][0].key?('best'), a.slice('slug', 'total', 'ranked'))
ranks = a['apis'].map { _1['rank'] }
check.call('provider best rank first', ranks.compact == ranks.compact.sort && (ranks.index(nil) || ranks.size) >= ranks.compact.size, ranks.inspect)
a = D::Provider.new.call(slug: 'Brîght Dâta')
check.call('provider an accented name', a['slug'] == 'bright-data', a['slug'] || a['error'])
in_ractor = Ractor.new { LLM::Datacircle::Provider.new.call(slug: 'Brîght Dâta') }
a = in_ractor.respond_to?(:value) ? in_ractor.value : in_ractor.take
check.call('provider in a ractor of its own', a['slug'] == 'bright-data' && a['total'].positive?, a['slug'] || a['error'])
a = D::Provider.new.call(slug: 'email-finder')
check.call('provider an API slug sent', a['error'].to_s.include?('datacircle-best-plans'), a['error'])
a = D::Provider.new.call
check.call('provider no slug', a['error'].to_s.start_with?("Give a provider's slug"), a['error'])
a = D::BestPlans.new.call(slug: 'email-finder', limit: nil, extra: 1)
check.call('null a key left out, an extra key dropped', a['plans'].size == 10, a['plans'].size)

# llm.rb's own LLM::Function, as a context runs a model's tool call: string keys in an LLM::Object, a Return back.
run = lambda do |tool, arguments|
  function = tool.function.dup
  function.id = 'call_1'
  function.arguments = arguments
  function.call
end
r = run.call(D::BestPlans, { 'slug' => 'email-finder', 'limit' => 2 })
check.call('Function#call, string keys', r.is_a?(LLM::Function::Return) && r.name == 'datacircle-best-plans' && r.value['plans'].size == 2 && !r.error?, r.value['plans'].map { _1['provider'] }.inspect)
r = run.call(D::SearchPlans, { 'query' => 'apollo', 'limit' => 1 })
check.call('Function#call search', r.value['plans'][0]['provider'].to_s.downcase.include?('apollo'), r.value['plans'][0]&.slice('provider', 'plan'))
r = run.call(D::Provider, { 'slug' => 'apollo' })
check.call('Function#call provider', r.value['slug'] == 'apollo', r.value.slice('provider', 'total'))
r = run.call(D::ListApis, {})
check.call('Function#call no arguments', r.value['apis'].size == 20, r.value['total'])
r = run.call(D::ListApis, nil)
check.call('Function#call nil arguments', r.value['apis'].size == 20, r.value['total'])

# The API down: Calls raises, and llm.rb gives a tool's raise to the model as an in-band error.
begin
  D::Calls.new(base_url: 'http://127.0.0.1:9/v1').best_plans(slug: 'email-finder')
  check.call('the API down raises', false)
rescue D::Error => e
  check.call('the API down raises', e.message.start_with?("Datacircle's API could not be reached"), e.message)
end
down = Class.new(LLM::Tool) do
  name 'down-best-plans'
  parameter :slug, String, 'slug'
  define_method(:call) { |slug: nil, **| D::Calls.new(base_url: 'http://127.0.0.1:9/v1').best_plans(slug: slug) }
end
f = down.function.dup
f.arguments = { 'slug' => 'email-finder' }
r = f.call
check.call('the API down, an in-band error', r.error? && r.value[:type] == 'LLM::Datacircle::Error', r.value[:message])
LLM::Tool.unregister(down)

puts failed.zero? ? 'ALL OK' : "FAILED #{failed}"
exit(failed.zero? ? 0 : 1)
