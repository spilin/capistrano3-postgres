namespace :load do
  task :defaults do
    set :postgres_backup_dir, -> { 'postgres_backup' }
    set :postgres_role, :app
    set :postgres_env, -> { fetch(:rack_env, fetch(:rails_env, fetch(:stage))) }
    set :postgres_remote_sqlc_file_path, -> { nil }
    set :postgres_local_database_config, -> { nil }
    set :postgres_remote_database_config, -> { nil }
  end
end

namespace :postgres do

  namespace :backup do

    desc 'Create database dump'
    task :create do
      grab_remote_database_config
      on roles(fetch(:postgres_role)) do |role|
        config = fetch(:postgres_remote_database_config)

        unless fetch(:postgres_remote_sqlc_file_path)
          file_name = "db_backup.#{Time.now.strftime('%Y-%m-%d_%H-%M-%S')}.sqlc"
          set :postgres_remote_sqlc_file_path, "#{shared_path}/#{fetch(:postgres_backup_dir)}/#{file_name}"
        end

        execute :pg_dump, "-U #{config['user'] || config['username']} -h #{config['host']} -Fc --file=#{fetch(:postgres_remote_sqlc_file_path)} #{config['database']}" do |ch, stream, out|
          ch.send_data "#{config['password']}\n" if out =~ /^Password:/
        end
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
            execute :pg_restore, "-c -U #{config['user'] || config['username']} -W --no-owner -h #{config['host']} -d #{fetch(:database_name)} #{file_path}" do |ch, stream, out|
              ch.send_data "#{config['password']}\n" if out =~ /^Password:/
            end
          rescue SSHKit::Command::Failed => e
            warn e.inspect
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
  end

  desc 'Replecate database locally'
  task :replicate do
    grab_local_database_config
    config = fetch(:postgres_local_database_config)
    ask(:database_name, config['database'])
    invoke "postgres:backup:create"
    invoke "postgres:backup:download"
    invoke "postgres:backup:import"
  end

  # Grabs local database config before importing dump
  def grab_local_database_config
    return if fetch(:postgres_local_database_config)
    on roles(fetch(:postgres_role)) do |role|
      run_locally do
        env = 'development'
        yaml_content = capture "cat config/database.yml"
        set :postgres_local_database_config,  YAML::load(yaml_content)[env]
      end
    end
  end

  # Grabs remote database config before creating dump
  def grab_remote_database_config
    return if fetch(:postgres_remote_database_config)
    on roles(fetch(:postgres_role)) do |role|
      env = fetch(:postgres_env).to_s.downcase
      yaml_content = capture "cat #{deploy_to}/current/config/database.yml"
      set :postgres_remote_database_config,  YAML::load(yaml_content)[env]
    end
  end

end
