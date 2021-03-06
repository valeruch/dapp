module Dapp
  module Kube
    class Helm::Release
      include Helper::YAML

      attr_reader :dapp

      attr_reader :name
      attr_reader :repo
      attr_reader :image_version
      attr_reader :namespace
      attr_reader :chart_path
      attr_reader :set
      attr_reader :values
      attr_reader :deploy_timeout

      def initialize(dapp,
        name:, repo:, image_version:, namespace:, chart_path:,
        set: [], values: [], deploy_timeout: nil)
        @dapp = dapp

        @name = name
        @repo = repo
        @image_version = image_version
        @namespace = namespace
        @chart_path = chart_path
        @set = set
        @values = values
        @deploy_timeout = deploy_timeout
      end

      def jobs
        (resources_specs['Job'] || {}).map do |name, spec|
          [name, Kubernetes::Client::Resource::Job.new(spec)]
        end.to_h
      end

      def hooks
        jobs.select do |_, spec|
          spec.annotations.key? "helm.sh/hook"
        end
      end

      def deployments
        (resources_specs['Deployment'] || {}).map do |name, spec|
          [name, Kubernetes::Client::Resource::Deployment.new(spec)]
        end.to_h
      end

      def deploy!
        args = [
          name, chart_path, additional_values,
          set_options, extra_options
        ].flatten

        dapp.kubernetes.create_namespace!(namespace) unless dapp.kubernetes.namespace?(namespace)

        dapp.shellout! "helm upgrade #{args.join(' ')}", verbose: true
      end

      protected

      def evaluation_output
        @evaluation_output ||= begin
          args = [
            name, chart_path, additional_values,
            set_options, extra_options(dry_run: true)
          ].flatten

          dapp.shellout!("helm upgrade #{args.join(' ')}").stdout
        end
      end

      def resources_specs
        @resources_specs ||= {}.tap do |specs|
          generator = proc do |text|
            text.split(/# Source.*|---/).reject {|c| c.strip.empty? }.map {|c| yaml_load(c) }.each do |spec|
              specs[spec['kind']] ||= {}
              specs[spec['kind']][(spec['metadata'] || {})['name']] = spec
            end
          end

          hook_start_index = nil
          if ind = evaluation_output.lines.index("HOOKS:\n")
            hook_start_index =  ind + 1
          else
            warn "[WARN][DEBUG INFO] Cannot find HOOKS section in helm dry-run output:"
          end

          manifest_start_index = nil
          if ind = evaluation_output.lines.index("MANIFEST:\n")
            manifest_start_index = ind + 1
          else
            warn "[WARN][DEBUG INFO] Cannot find MANIFEST section in helm dry-run output:"
          end

          happy_helming_start_index = evaluation_output.lines.index("Release \"#{name}\" has been upgraded. Happy Helming!\n")

          generator.call(evaluation_output.lines[hook_start_index..manifest_start_index-2].join) if hook_start_index and manifest_start_index
          if manifest_start_index
            if happy_helming_start_index
              generator.call(evaluation_output.lines[manifest_start_index..happy_helming_start_index-2].join)
            else
              generator.call(evaluation_output.lines[manifest_start_index..-1].join)
            end
          end
        end
      end

      def additional_values
        [].tap do |options|
          options.concat(values.map { |p| "--values #{p}" })
        end
      end

      def set_options
        [].tap do |options|
          options << "--set global.dapp.repo=#{repo}"
          options << "--set global.dapp.image_version=#{image_version}"
          options << "--set global.namespace=#{namespace}"
          options.concat(set.map { |opt| "--set #{opt}" })
        end
      end

      def extra_options(dry_run: nil)
        dry_run = dapp.dry_run? if dry_run.nil?

        [].tap do |options|
          options << "--namespace #{namespace}"
          options << '--install'
          options << '--dry-run' if dry_run
          options << '--debug'   if dry_run || dapp.log_verbose?
          options << "--timeout #{deploy_timeout}" if deploy_timeout
        end
      end
    end # Helm::Release
  end # Kube
end # Dapp
