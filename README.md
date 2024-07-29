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
companies = quartr.companies

companies = quartr.search_ticker(query: 'AA')
companies = quartr.search_name(query: 'Microsoft')
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/web2boomer/quartr.git](https://github.com/web2boomer/quartr.git). 