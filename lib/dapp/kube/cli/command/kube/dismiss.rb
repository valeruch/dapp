module Dapp::Kube::CLI::Command
  class Kube < ::Dapp::CLI
    class Dismiss < Base
      banner <<BANNER.freeze
Usage:

  dapp kube dismiss [options]

Options:
BANNER

      option :namespace,
             long: '--namespace NAME',
             default: nil

      option :with_namespace,
             long: '--with-namespace',
             default: false
    end
  end
end
