# Capistrano3::Postgres

## Installation

Add this line to your application's Gemfile:

    gem 'capistrano3-postgres'

or:

    gem 'capistrano3-postgres' , group: :development

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install capistrano3-postgres

## Usage
```ruby
    # Capfile

    require 'capistrano3/postgres'
```

then you can use ```cap -vT``` to list tasks
```
cap postgres:backup:create
cap postgres:backup:download
cap postgres:backup:import
cap postgres:replicate
```
You will be prompted for password and local database name that you want to use for restore.

Sometimes it's a good idea to create dump before each deploy.
```
before 'deploy:starting', 'postgres:backup:create'
```


## Contributing

1. Fork it ( http://github.com/spilin/capistrano3-postgres/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request






