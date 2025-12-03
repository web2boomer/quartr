# quartr 

[Quartr](https://quartr.com/) API wrapper for Ruby. Full API reference here: https://docs.quartr.com/v2/reference

Quartr is transforming the way finance professionals conduct qualitative public market research.

## Installation

Install the gem and add to the application's Gemfile by executing:

```
$ bundle add quartr
```

If bundler is not being used to manage dependencies, install the gem by executing:

```
$ gem install quartr 
```

## Usage

First instantiate a Quartr API client:

```ruby
quartr = Quartr::API.new(ENV['YOUR_QUARTR_API_KEY'])
```

You can also set the env var YOUR_QUARTR_API_KEY and then just call.

```ruby
quartr = Quartr::API.new
```

_*If you have a demo key and so need to access demo API at api-demo.quartr.com rather than api.quartr.com set QUARTR_DEMO env var to 'yes' e.g. export QUARTR_DEMO=yes*_

Now we can do all sorts...

(Companies)[https://docs.quartr.com/v2/reference#tag/company]

```ruby
# List companies with default pagination
companies = quartr.companies

# List companies with filtering options
companies = quartr.companies(countries: "US", exchanges: "NasdaqGS", limit: 100)
companies = quartr.companies(tickers: "AAPL,MSFT,GOOGL")
companies = quartr.companies(updated_after: "2024-01-01")

# Pagination with cursor
first_page = quartr.companies(limit: 50, cursor: 0)
next_page = quartr.companies(limit: 50, cursor: first_page['pagination']['nextCursor'])

# Retrieve a specific company by ID
company = quartr.company(company_id: 3624) # Nvidia

# Retrieve a company by ticker
company = quartr.company(ticker: "NVDA") # Nvidia

# List events with filtering
events = quartr.events(tickers: "NVDA", limit: 50)
events = quartr.events(start_date: "2025-01-01", end_date: "2025-12-31")
events = quartr.quartr.companies(tickers: "AAPL,MSFT,GOOG")

# Paginate through events
first_events = quartr.events(limit: 100, cursor: 0)
next_events = quartr.events(limit: 100, cursor: first_events['pagination']['nextCursor'])

# Retrieve a specific event
event = quartr.event(12345)
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/web2boomer/quartr.git](https://github.com/web2boomer/quartr.git). 