#
# Author:: Vianney Foucault (<vianney.foucault@gmail.com>)
# Copyright:: Copyright (c) 2015
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/knife'
require 'chef/knife/power_common'
require 'chef/knife/power_common_config'

class Chef
  class Knife
    class PowerLparFind < Knife
      ###
      ### Get hosting system for a lpar
      ###
      banner "knife power lpar find -n lparname [options]"

      option :partition,
        :short => "-n PARTITION",
        :long => "--partition PARTITION",
        :description => "Partition Name"

      option :debug,
        :long => "--debug",
	:description => "set the debug flag"

      #
      # Run the plugin
      #

      def run
        check_params
        findlpar
      end

      def check_params
	initsettings()
	 if config[:debug]
          debug = true
        else
          debug = false
        end
        if not config[:partition].nil?
          @actions = "partition"
          ui.info "Will find partition #{ui.color(config[:partition], :cyan)} on hmc #{ui.color(config[:hmc], :cyan)}"
        else
          ui.error "Wrong parameters usage"
          show_usage
          exit 1
        end
      end

      def findlpar
	myhmc = PowerVMTools::HMC.new(config[:hmc],{ :user => config[:hmc_user], :passwd => config[:hmcpasswd], :port => config[:ssh_port],:debug => debug })
	runningframes = myhmc.framesbystatus("Operating")
	runningframes.each do |frame|
          myframe = PowerVMTools::Frame.new(frame,myhmc)
          if myframe.getlpars.include?(config[:partition])
	    ui.info "Partition #{ui.color(config[:partition], :cyan)} is hosted on frame #{ui.color(frame, :cyan)}"
	    exit 0
	  end
        end
        ui.error "Partition #{ui.color(config[:partition], :cyan)} not found on hmc #{ui.color(config[:hmc],:cyan)}"
        exit 1
      end
    end
  end
end
