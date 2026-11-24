# Datacircle tools for llm.rb

Find the best GTM APIs. We benchmark all the GTM APIs and we put the results on our website.

Our website: https://datacircle.dev

This gem gives [llm.rb](https://github.com/r-uby-dev/llm) four tools that call Datacircle's open API, https://api.datacircle.dev/v1. Each tool is a class of `LLM::Tool`, for an agent or a context. You need no key and no account.

| Tool | What the tool gives | Call |
| --- | --- | --- |
| `datacircle-list-apis` | Every GTM API on Datacircle, with the API's slug, number of plans, number of providers and best plan | `GET /apis` |
| `datacircle-best-plans` | One API's plans, sorted by score out of 100, best first. Each plan comes with a rank and a price per 1,000 calls | `GET /apis/{slug}/best` |
| `datacircle-search-plans` | Plans that match a provider or plan name, on all APIs or on one API. You can sort them by score, provider or price | `GET /plans` |
| `datacircle-provider` | The APIs a provider sells, and the provider's rank on each API | `GET /providers/{slug}` |

## Install

```bash
gem install llm.rb-datacircle
```

Or add it to your Gemfile:

```ruby
gem "llm.rb-datacircle"
```

The gem needs llm.rb 16 or later and Ruby 3.4 or later. llm.rb 18 and later need Ruby 4.

## Use the tools with an agent

```ruby
require "llm"
require "llm/datacircle"

llm = LLM.openai(key: ENV["OPENAI_API_KEY"])
agent = LLM::Agent.new(llm, tools: LLM::Datacircle.tools)
res = agent.talk "Which email finder API is best for under $5 per 1,000?"
puts res.content
```

The agent runs the tool calls of the model and sends the answers back. Each tool is a class: `LLM::Datacircle::ListApis`, `BestPlans`, `SearchPlans` and `Provider`. Give an agent only the ones it needs, or add them to your own tools:

```ruby
class PlanFinder < LLM::Agent
  tools LLM::Datacircle::BestPlans, LLM::Datacircle::SearchPlans
end

res = PlanFinder.new(llm).talk "Who is best for the SERP API?"
puts res.content
```

The tools run on each concurrency strategy of llm.rb: `:sequential` (the default), `:thread`, `:fiber`, `:async`, `:fork` and `:ractor`. `:ractor` needs Ruby 4, as the Net::HTTP of Ruby 3.4 can't run in a ractor. Run the tools on threads like this:

```ruby
agent = LLM::Agent.new(llm, tools: LLM::Datacircle.tools, concurrency: :thread)
puts agent.talk("Rank Bright Data on each API it sells").content
```

With a context, you run the tool calls yourself:

```ruby
ctx = LLM::Context.new(llm, tools: LLM::Datacircle.tools)
ctx.talk "What are the 3 cheapest plans of the email-finder API?"
ctx.talk(ctx.wait(:thread)) while ctx.pending_functions?
puts ctx.messages.to_a.select(&:assistant?).last.content
```

## Call a tool yourself

You can call a tool without a model. You get the tool's answer as a Hash:

```ruby
LLM::Datacircle::BestPlans.new.call(slug: "email-finder", limit: 3)
# => {"api" => "Employee email", "slug" => "email-finder", ..., "plans" => [{"api" => "Employee email", "rank" => 1, ...}]}
```

`LLM::Datacircle::Calls.new` makes the same calls. The methods of `Calls` are `list_apis`, `best_plans`, `search_plans` and `provider`. `LLM::Datacircle::Calls.new(base_url: ...)` calls another address, for example a proxy of yours.

## What the model reads

Each plan comes with a rank, provider, plan, score, price per 1,000 (`perThousand`, in dollars) and a page on datacircle.dev. That page lists every field. A tool also takes an API's name or a provider's name in place of a slug.

For an unknown slug, the model reads `{"error" => "..."}` with the API's message and what to send instead. If the network fails, the tool raises `LLM::Datacircle::Error`. llm.rb gives the model that error and the agent keeps going.

## Network

Each tool call sends HTTPS GET requests to https://api.datacircle.dev/v1 and nowhere else. Most calls send one request. A tool sends up to four when the model gives a name in place of a slug. The requests hold only the tool's input from the model: no key and nothing from your messages. The API takes up to 60 calls a minute from one IP address. A tool waits once, for a minute at most, when the API asks for a wait. The gem's one dependency is llm.rb. The gem stores nothing.

## Links

- Datacircle: https://datacircle.dev
- The API: https://datacircle.dev/api
- The API's spec: https://api.datacircle.dev/v1/openapi.json
- What each key means: https://datacircle.dev/fields

MIT license.
