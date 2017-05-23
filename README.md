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

Capistrano3::Postgres supports [Dotenv](https://github.com/bkeepers/dotenv) and [Figaro](https://github.com/laserlemon/figaro) gems and automatically loads environment variables from `.env`/`application.yml` files if they are used in the project.

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

All downloaded dump files will be deleted after importing. If you want to keep them, you can set:
```
set :postgres_keep_local_dumps, 5 # Will keep 5 last dump files.
```

To save on disk space, you can set the compression level. Gzip 0-9 are supported, default is 0:
```
set :postgres_backup_compression_level, 6 # Will use gzip level 6 to compress the output.
```

If you are using different clusters:
```
set :postgres_remote_cluster, '9.6/main'
```

## Contributing

1. Fork it ( http://github.com/spilin/capistrano3-postgres/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
