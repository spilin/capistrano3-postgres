namespace :load do
  task :defaults do
    set :postgres_backup_dir, -> { 'postgres_backup' }
    set :postgres_role, :db
    set :postgres_env, -> { fetch(:rack_env, fetch(:rails_env, fetch(:stage))) }
    set :postgres_keep_local_dumps, 0
    set :postgres_remote_sqlc_file_path, -> { nil }
    set :postgres_local_database_config, -> { nil }
    set :postgres_remote_database_config, -> { nil }
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

        execute "PGPASSWORD=#{config['password']} pg_dump -U #{config['username'] || config['user']} -h #{config['host']} -Fc --file=#{fetch(:postgres_remote_sqlc_file_path)} #{config['database']}"
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
            execute "PGPASSFILE=#{pgpass_path} pg_restore -c -U #{config['username'] || config['user']} --no-owner -h #{config['host']} -p #{config['port'] || 5432 } -d #{fetch(:database_name)} #{file_path}"
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

  desc 'Replecate database locally'
  task :replicate do
    grab_local_database_config
    config = fetch(:postgres_local_database_config)
    ask(:database_name, config['database'])
    invoke "postgres:backup:create"
    invoke "postgres:backup:download"
    invoke "postgres:backup:import"
    invoke("postgres:backup:cleanup") if fetch(:postgres_keep_local_dumps) > 0
  end

  # Grabs local database config before importing dump
  def grab_local_database_config
    return if fetch(:postgres_local_database_config)
    on roles(fetch(:postgres_role)) do |role|
      run_locally do
        env = 'development'
        yaml_content = capture "cat config/database.yml"
        set :postgres_local_database_config,  database_config_defaults.merge(YAML::load(yaml_content)[env])
      end
    end
  end

  # Grabs remote database config before creating dump
  def grab_remote_database_config
    return if fetch(:postgres_remote_database_config)
    on roles(fetch(:postgres_role)) do |role|
      env = fetch(:postgres_env).to_s.downcase
      yaml_content = capture "cat #{deploy_to}/current/config/database.yml"
      set :postgres_remote_database_config,  database_config_defaults.merge(YAML::load(yaml_content)[env])
    end
  end

  def database_config_defaults
    { 'host' => 'localhost', 'user' => 'postgres' }
  end

end
