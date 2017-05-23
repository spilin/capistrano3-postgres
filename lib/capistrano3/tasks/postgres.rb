namespace :load do
  task :defaults do
    set :postgres_backup_dir, -> { 'postgres_backup' }
    set :postgres_role, :db
    set :postgres_env, -> { fetch(:rack_env, fetch(:rails_env, fetch(:stage))) }
    set :postgres_keep_local_dumps, 0
    set :postgres_backup_compression_level, 0
    set :postgres_remote_sqlc_file_path, -> { nil }
    set :postgres_local_database_config, -> { nil }
    set :postgres_remote_database_config, -> { nil }
    set :postgres_remote_cluster, -> { nil }
  end
end

namespace :postgres do
  namespace :backup do
    desc 'Create database dump'
    task :create do
      on roles(fetch(:postgres_role)) do |role|
        grab_remote_database_config
        config = fetch(:postgres_remote_database_config)

        unless fetch(:postgres_remote_sqlc_file_path)
          file_name = "db_backup.#{Time.now.strftime('%Y-%m-%d_%H-%M-%S')}.sqlc"
          set :postgres_remote_sqlc_file_path, "#{shared_path}/#{fetch(:postgres_backup_dir)}/#{file_name}"
        end
        execute [
          "PGPASSWORD=#{config['password']}",
          "pg_dump #{user_option(config)}",
          "-h #{config['host']}",
          config['port'] ? "-p #{config['port']}" : nil,
          "-Fc",
          "--file=#{fetch(:postgres_remote_sqlc_file_path)}",
          "-Z #{fetch(:postgres_backup_compression_level)}",
          fetch(:postgres_remote_cluster) ? "--cluster #{fetch(:postgres_remote_cluster)}" : nil,
          "#{config['database']}"
        ].compact.join(' ')
      end
    end

    desc 'Download last database dump'
    task :download do
      on roles(fetch(:postgres_role)) do |role|
        unless fetch(:postgres_remote_sqlc_file_path)
          file_name = capture("ls -v #{shared_path}/#{fetch :postgres_backup_dir}").split(/\n/).last
          set :postgres_remote_sqlc_file_path, "#{shared_path}/#{fetch :postgres_backup_dir}/#{file_name}"
        end

        download!(fetch(:postgres_remote_sqlc_file_path), "tmp/#{fetch :postgres_backup_dir}/#{Pathname.new(fetch(:postgres_remote_sqlc_file_path)).basename}")
        begin
          remote_file = fetch(:postgres_remote_sqlc_file_path)
        rescue SSHKit::Command::Failed => e
          warn e.inspect
        ensure
          execute "rm #{remote_file}"
        end
      end
    end

    desc "Import last dump"
    task :import do
      grab_local_database_config
      run_locally do
        config = fetch(:postgres_local_database_config)

        unless fetch(:database_name)
          ask(:database_name, config['database'])
        end

        with rails_env: :development do
          file_name = capture("ls -v tmp/#{fetch :postgres_backup_dir}").split(/\n/).last
          file_path = "tmp/#{fetch :postgres_backup_dir}/#{file_name}"
          begin
            pgpass_path = File.join(Dir.pwd, '.pgpass')
            File.open(pgpass_path, 'w+', 0600) { |file| file.write("*:*:*:#{config['username'] || config['user']}:#{config['password']}") }
            execute "PGPASSFILE=#{pgpass_path} pg_restore -c #{user_option(config)} --no-owner -h #{config['host']} -p #{config['port'] || 5432 } -d #{fetch(:database_name)} #{file_path}"
          rescue SSHKit::Command::Failed => e
            warn e.inspect
            info 'Import performed successfully!'
          ensure
            File.delete(pgpass_path) if File.exist?(pgpass_path)
            File.delete(file_path) if (fetch(:postgres_keep_local_dumps) == 0) && File.exist?(file_path)
          end
        end
      end
    end

    # Ensure that remote dirs for postgres backup exist
    before :create, :ensure_remote_dirs do
      on roles(fetch(:postgres_role)) do |role|
        execute :mkdir, "-p #{shared_path}/#{fetch(:postgres_backup_dir)}"
      end
    end

    # Ensure that loca dirs for postgres backup exist
    before :download, :ensure_local_dirs do
      on roles(fetch(:postgres_role)) do |role|
        run_locally do
          execute :mkdir, "-p  tmp/#{fetch :postgres_backup_dir}"
        end
      end
    end

    desc "Cleanup old local dumps"
    task :cleanup do
      run_locally do
        dir = "tmp/#{fetch :postgres_backup_dir}"
        file_names = capture("ls -v #{dir}").split(/\n/).sort
        file_names[0...-fetch(:postgres_keep_local_dumps)].each {|file_name| File.delete("#{dir}/#{file_name}") }
      end
    end
  end

  desc 'Replicate database locally'
  task :replicate do
    grab_local_database_config
    config = fetch(:postgres_local_database_config)
    ask(:database_name, config['database'])
    invoke "postgres:backup:create"
    invoke "postgres:backup:download"
    invoke "postgres:backup:import"
    invoke("postgres:backup:cleanup") if fetch(:postgres_keep_local_dumps) > 0
  end

  def user_option(config)
    if config['user'] || config['username']
      "-U #{config['user'] || config['username']}"
    else
      '' # assume ident auth is being used
    end
  end

  # Grabs local database config before importing dump
  def grab_local_database_config
    return if fetch(:postgres_local_database_config)
    on roles(fetch(:postgres_role)) do |role|
      run_locally do
        env = 'development'
        preload_env_variables(env)
        yaml_content = ERB.new(capture 'cat config/database.yml').result
        set :postgres_local_database_config,  database_config_defaults.merge(YAML::load(yaml_content)[env])
      end
    end
  end

  # Grabs remote database config before creating dump
  def grab_remote_database_config
    return if fetch(:postgres_remote_database_config)
    on roles(fetch(:postgres_role)) do |role|
      within release_path do
        env = fetch(:postgres_env).to_s.downcase
        filename = "#{deploy_to}/current/config/database.yml"
        eval_yaml_with_erb = <<-RUBY.strip
          #{env_variables_loader_code(env)}
          require 'erb'
          puts ERB.new(File.read('#{filename}')).result
        RUBY

        capture_config_cmd = "ruby -e \"#{eval_yaml_with_erb}\""
        yaml_content = test('ruby -v') ? capture(capture_config_cmd) : capture(:bundle, :exec, capture_config_cmd)
        set :postgres_remote_database_config,  database_config_defaults.merge(YAML::load(yaml_content)[env])
      end
    end
  end

  def database_config_defaults
    { 'host' => 'localhost' }
  end

  # Load environment variables for configurations.
  # Useful for such gems as Dotenv, Figaro, etc.
  def preload_env_variables(env)
    safely_require_gems('dotenv', 'figaro')

    if defined?(Dotenv)
      load_env_variables_with_dotenv(env)
    elsif defined?(Figaro)
      load_env_variables_with_figaro(env)
    end
  end

  def load_env_variables_with_dotenv(env)
    Dotenv.load(
      File.expand_path('.env.local'),
      File.expand_path(".env.#{env}"),
      File.expand_path('.env')
    )
  end

  def load_env_variables_with_figaro(env)
    config = 'config/application.yml'

    Figaro.application = Figaro::Application.new(environment: env, path: config)
    Figaro.load
  end

  def safely_require_gems(*gem_names)
    gem_names.each do |name|
      begin
        require name
      rescue LoadError
        # Ignore if gem doesn't exist
      end
    end
  end

  # Requires necessary gems (Dotenv, Figaro, ...) if present
  # and loads environment variables for configurations
  def env_variables_loader_code(env)
    <<-RUBY.strip
      begin
        require 'dotenv'
        Dotenv.load(File.expand_path('.env.#{env}'), File.expand_path('.env'))
      rescue LoadError
      end

      begin
        require 'figaro'
        config = File.expand_path('../config/application.yml', __FILE__)

        Figaro.application = Figaro::Application.new(environment: '#{env}', path: config)
        Figaro.load
      rescue LoadError
      end
    RUBY
  end
end
