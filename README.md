# Capistrano3::Postgres

## Installation

Add this line to your application's Gemfile:

    gem 'capistrano3-postgres', require: false

or:

    gem 'capistrano3-postgres', require: false, group: :development

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
cap postgres:backup:create # Creates dump of a database(By default stores it to ../shared/postgres_backup directory)
cap postgres:backup:download # Downloads dump to local server(By default stores file in ./tmp/postgres_backup directory)
cap postgres:backup:import # Imports last dump file to local database of your choice.
cap postgres:replicate # Performs create, download and import step by step.
```
You will be prompted for password and local database name that you want to use for restore.
In most cases you will need to provide environment
```
cap production postgres:replicate
```

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






