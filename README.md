# quartr 

[Quartr](https://quartr.com/) API wrapper for Ruby. Full API reference here: https://quartr.dev/api-reference/companies/list-companies

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

Now we can make dollar...

## Companies

```ruby
# List companies with default pagination
companies = quartr.companies

# List companies with filtering options
companies = quartr.companies(countries: "US", exchanges: "NasdaqGS", limit: 100)
companies = quartr.companies(tickers: "AAPL,MSFT,GOOGL")
companies = quartr.companies(updated_after: "2024-01-01")
companies = quartr.companies(isins: "US0378331005", ids: "3624,1234")

# Pagination with cursor
first_page = quartr.companies(limit: 50, cursor: 0)
next_page = quartr.companies(limit: 50, cursor: first_page['pagination']['nextCursor'])

# Retrieve a specific company by ID
company = quartr.company(company_id: 3624) # Nvidia

# Retrieve a company by ticker
company = quartr.company(ticker: "NVDA") # Nvidia
```

## Events

```ruby
# List events with filtering
events = quartr.events(tickers: "NVDA", limit: 50)
events = quartr.events(start_date: "2025-01-01", end_date: "2025-12-31")
events = quartr.events(company_ids: "3624,1234", type_ids: "1,2,3")
events = quartr.events(countries: "US", exchanges: "NasdaqGS")
events = quartr.events(updated_after: "2024-01-01", sort_by: "date")

# Paginate through events
first_events = quartr.events(limit: 100, cursor: 0)
next_events = quartr.events(limit: 100, cursor: first_events['pagination']['nextCursor'])

# Retrieve a specific event
event = quartr.event(12345)
```

## Event Types

```ruby
# List event types
event_types = quartr.event_types

# Paginate through event types
first_page = quartr.event_types(limit: 50, cursor: 0)
next_page = quartr.event_types(limit: 50, cursor: first_page['pagination']['nextCursor'])
```

## Live Transcripts

```ruby
# List live transcripts with filtering
live_transcripts = quartr.live_transcripts(tickers: "NVDA", limit: 100)
live_transcripts = quartr.live_transcripts(countries: "US", states: "active")
live_transcripts = quartr.live_transcripts(event_ids: "12345,67890")

# Retrieve a specific live transcript
live_transcript = quartr.live_transcript(id: 12345)
```

## Document Types

```ruby
# List document types
document_types = quartr.document_types

# Paginate through document types
first_page = quartr.document_types(limit: 50, cursor: 0)
next_page = quartr.document_types(limit: 50, cursor: first_page['pagination']['nextCursor'])
```

## Transcripts

```ruby
# List transcripts with filtering
transcripts = quartr.transcripts(tickers: "NVDA", limit: 100)
transcripts = quartr.transcripts(start_date: "2025-01-01", end_date: "2025-12-31")
transcripts = quartr.transcripts(company_ids: "3624,1234", event_ids: "12345,67890")
transcripts = quartr.transcripts(type_ids: "1,2,3", document_group_ids: "10,20")
transcripts = quartr.transcripts(updated_after: "2024-01-01", expand: "company,event")

# Paginate through transcripts
first_page = quartr.transcripts(limit: 100, cursor: 0)
next_page = quartr.transcripts(limit: 100, cursor: first_page['pagination']['nextCursor'])

# Retrieve a specific transcript
transcript = quartr.transcript(12345)
transcript = quartr.transcript(12345, expand: "company,event")
```

## Slide Decks

```ruby
# List slide decks with filtering
slide_decks = quartr.slide_decks(tickers: "NVDA", limit: 100)
slide_decks = quartr.slide_decks(start_date: "2025-01-01", end_date: "2025-12-31")
slide_decks = quartr.slide_decks(company_ids: "3624,1234", event_ids: "12345,67890")
slide_decks = quartr.slide_decks(type_ids: "1,2,3", document_group_ids: "10,20")
slide_decks = quartr.slide_decks(updated_after: "2024-01-01", expand: "company,event")

# Paginate through slide decks
first_page = quartr.slide_decks(limit: 100, cursor: 0)
next_page = quartr.slide_decks(limit: 100, cursor: first_page['pagination']['nextCursor'])
```

## Reports

```ruby
# List reports with filtering
reports = quartr.reports(tickers: "NVDA", limit: 100)
reports = quartr.reports(start_date: "2025-01-01", end_date: "2025-12-31")
reports = quartr.reports(company_ids: "3624,1234", event_ids: "12345,67890")
reports = quartr.reports(type_ids: "1,2,3", document_group_ids: "10,20")
reports = quartr.reports(updated_after: "2024-01-01", expand: "company,event")

# Paginate through reports
first_page = quartr.reports(limit: 100, cursor: 0)
next_page = quartr.reports(limit: 100, cursor: first_page['pagination']['nextCursor'])

# Retrieve a specific report
report = quartr.report(12345)
report = quartr.report(12345, expand: "company,event")
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/web2boomer/quartr.git](https://github.com/web2boomer/quartr.git). 