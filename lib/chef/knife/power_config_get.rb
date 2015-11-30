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
require 'json'
require 'pp'

class Chef
  class Knife
    class PowerConfigGet < Knife
      include Chef::Knife::PowerCommon
      ###
      ### Get LPARs Configuration & profiles
      ###
      banner "knife power config get [options]"

      option :configfile,
        :short => "-C configfile",
        :long => "--config-file configfile",
        :description => "optional configuration to use",
	:default => "~/knife-power-config.yml"

      option :output_format,
        :short => "-o FORMAT (csv)",
        :long => "--export-format FORMAT (csv|json)",
        :description => "output format for specified format"

      option :managed_host,
        :short => "-m MANAGED_HOST",
        :long => "--managed-host MANAGED_HOST",
        :description => "Managed Host Name"

      option :partition,
        :short => "-n PARTITION",
        :long => "--partition PARTITION",
        :description => "Partition Name"

      option :all_servers,
        :short => "-a",
        :long => "--all-servers",
        :description => "Fetch all partitions"

      option :export_config,
        :short => "-e DIRECTORY",
        :long => "--export-config DIRECTORY",
        :description => "Export profile to a json file"

      option :only_current_profile,
        :long => "--only-current",
        :description => "Display on the current profile"

      option :debug,
        :long => "--debug",
        :description => "set the debug flag"

      #
      # Run the plugin
      #

      def run
	if config[:debug]
          debug = true
        else
          debug = false
        end
	initsettings()
        check_params

        #### start
	myhmc = PowerVMTools::HMC.new(config[:hmc],{ :user => config[:hmc_user], :passwd => config[:hmcpasswd], :port => config[:ssh_port],:debug => debug })
	runningframes = myhmc.framesbystatus("Operating")
	hash_config = Hash.new
	if config[:all_servers]
          ui.info "Will fetch all partitions from all managed hosts on hmc #{ui.color(config[:hmc], :cyan)}"
	  runningframes.each do |frame|
	    hash_config[frame] = Array.new
	    myframe = PowerVMTools::Frame.new(frame,myhmc)
	    lpars = myframe.getlpars()
	    lpars.each do |lpar|
	      mylpar = PowerVMTools::Lpar.new(lpar,{:frame => myframe})
	      hashref = mylpar.config
	      hashref[:profiles] = mylpar.profiles
	      hash_config[frame].push(hashref)
 	    end
	  end
	elsif not config[:managed_host].nil? and config[:partition].nil?
          ui.info "Will fetch all partitions from managed host #{ui.color(config[:managed_host], :cyan)} on hmc #{ui.color(config[:hmc], :cyan)}"
	  if not runningframes.include?(config[:managed_host])
	    ui.error "Frame #{config[:managed_host]} is not in the Operating state"
	    exit 1
	  else
	    myframe = PowerVMTools::Frame.new(config[:managed_host],myhmc)
	    hash_config[myframe.name] = Array.new
	    lpars = myframe.getlpars()
	    lpars.each do |lpar|
	      mylpar = PowerVMTools::Lpar.new(lpar,{:frame => myframe})
	      hashref = mylpar.config
	      hashref[:profiles] = mylpar.profiles
	      hash_config[myframe.name].push(hashref)
 	    end
	  end
	elsif not config[:managed_host].nil? and not config[:partition].nil?  	
          ui.info "Will fetch partition #{ui.color(config[:partition], :cyan)} from managed host #{ui.color(config[:managed_host], :cyan)} on hmc #{ui.color(config[:hmc], :cyan)}"
	  if not runningframes.include?(config[:managed_host])
            ui.error "Frame #{config[:managed_host]} is not in the Operating state"
            exit 1
	  else
	    myframe = PowerVMTools::Frame.new(config[:managed_host],myhmc)
            hash_config[config[:managed_host]] = Array.new
	    mylpar = PowerVMTools::Lpar.new(config[:partition], {:frame => myframe})
	    hashref = mylpar.config
	    hashref[:profiles] = mylpar.profiles
	    hash_config[config[:managed_host]].push(hashref)
	  end
	elsif config[:managed_host].nil? and not config[:partition].nil?
          ui.info "Will fetch partitions #{ui.color(config[:partition], :cyan)} on hmc #{ui.color(config[:hmc], :cyan)}"
	  ## tricky, we must find the owning frame from this HMC
	  runningframes.each do |frame|
	    myframe = PowerVMTools::Frame.new(frame,myhmc)
	    if myframe.getlpars.include?(config[:partition])
              hash_config[frame] = Array.new
	      mylpar = PowerVMTools::Lpar.new(config[:partition], {:frame => myframe})
	      hashref = mylpar.config
	      hashref[:profiles] = mylpar.profiles
	      hash_config[frame].push(hashref)
	    end
	  end
	else
	  ui.error "Wrong parameters usage"
          show_usage
          exit 1
        end
        if config[:output_format] == "csv"
          print_profile_csv(hash_config)
        elsif config[:output_format] == "json"
          print_profile_json(hash_config)
        else
          print_profile(hash_config)
        end
        if not config[:export_config].nil?
          export_config(hash_config,config[:export_config])
        end
      end
 

      def check_params
        if config[:hmc].nil?
          ui.error "No HMC parameter specified in configuration file"
          exit 1
        end
        if config[:export_config]
          if not File.directory?(config[:export_config])
            ui.error "Directory #{config[:export_config]} does not exists or not accessible !"
            exit 1
          end
        end
      end

      def export_config(hash_profile,directory)
        hash_profile.each do |sys, arraylpar|
          arraylpar.each do |lpar|
            lpar[:profiles].each do |item|
              file = directory + sys + "_" + lpar["name"] + "_" + item["name"] + ".json"
              savejson(item,file)
            end
          end
        end
      end

      def print_profile_csv(hash_profile)
        ui.info "Frame;LPARID;Partition;State;profile;CPU;CPUMode;CPUWeight;SharedProcPool;DESVP;MAXVP;DESEC;MAXEC;DESMEM;MAXMEM;AME"
        hash_profile.each do |sys, arraylpar|
          arraylpar.each do |lpar|
            defpro = lpar["default_profile"]
            curpro = lpar["curr_profile"]
            lpar[:profiles].each do |item|
              if item[:name] == defpro and item["name"] == curpro
                prof = item[:name] + "*+"
              elsif item[:name] == curpro
                prof = item[:name] + "+"
              elsif not config[:only_current_profile]
                if item[:name] == defpro
                  prof = item[:name] + "*"
                else
                  prof = item[:name]
                end
              else
                next
              end
              print "#{sys};#{item[:lpar_id]};#{item["lpar_name"]};#{lpar["state"]};#{prof};#{item["proc_mode"]};"
              if item[:proc_mode] == "shared"
                print "#{item[:sharing_mode]};#{item["uncap_weight"]};#{item["shared_proc_pool_name"]};"
              else
                print "N/A;N/A;N/A;"
              end
              print "#{item[:desired_procs]};#{item["max_procs"]};#{item["desired_proc_units"]};#{item["max_proc_units"]};"
              formated_mem = item[:desired_mem].to_f / 1024
              formated_max_mem = item[:max_mem].to_f / 1024
              print "#{formated_mem.to_s};#{formated_max_mem.to_s};#{item[:mem_expansion]}\n"
            end
          end
        end
      end

      def print_profile(hash_profile)
        hash_profile.each do |sys, arraylpar|
          profile_list = [
            ui.color('Partition ID', :cyan),
            ui.color('Partition', :cyan),
            ui.color('State', :cyan),
            ui.color('Profile', :cyan),
            ui.color('CPU Type', :cyan),
            ui.color('CPU Mode', :cyan),
            ui.color('CPU Weight', :cyan),
            ui.color('SharedProcPool', :cyan),
            ui.color('Desired VP', :cyan),
            ui.color('Max VP', :cyan),
            ui.color('Desired EC', :cyan),
            ui.color('Max EC', :cyan),
            ui.color('Desired Memory', :cyan),
            ui.color('Max Memory', :cyan),
            ui.color('AME Factor', :cyan),
          ].flatten.compact
          ui.info "Managed system : #{ui.color(sys, :cyan)}"
          arraylpar.each do |lpar|
            defpro = lpar["default_profile"]
            curpro = lpar["curr_profile"]
            lpar[:profiles].each do |item|
              if item[:name] == defpro and item["name"] == curpro
                prof = item[:name] + "*+"
              elsif item[:name] == curpro
                prof = item[:name] + "+"
              elsif not config[:only_current_profile]
                if item[:name] == defpro
                  prof = item[:name] + "*"
                else
                  prof = item[:name]
                end
              else
                next
              end
              profile_list << item[:lpar_id]
              profile_list << item[:lpar_name]
              profile_list << lpar["state"]
              profile_list << prof
              profile_list << item[:proc_mode]
              if item[:proc_mode] == "shared"
                profile_list << item[:sharing_mode]
                profile_list << item[:uncap_weight]
                profile_list << item[:shared_proc_pool_name]
              else
                profile_list << "N/A"
                profile_list << "N/A"
                profile_list << "N/A"
              end
              profile_list << item[:desired_procs]
              profile_list << item[:max_procs]
              profile_list << item[:desired_proc_units]
              profile_list << item[:max_proc_units]
              formated_mem = item[:desired_mem].to_f / 1024
              formated_max = item[:max_mem].to_f / 1024
              profile_list << formated_mem.to_s
              profile_list << formated_max.to_s
              profile_list << item[:mem_expansion]
            end
          end
          puts ui.list(profile_list, :uneven_columns_across, 15)
          ui.info "\n"
        end
        ui.info "* denotes the default profile"
        ui.info "+ denotes the current profile"
        ui.info "\n"
      end

      def getconfig
        hash_profile = Hash.new(Array.new)
        case @actions
        when "partition"
          hash_profile = getlparconfig(config[:managed_host],config[:partition])
        when "managedhost"
          array_lpars = getlparlist(config[:managed_host])
          hash_profile[config[:managed_host]] = Array.new
          array_lpars.each do |lpar|
            hash_lpar =  getlparconfig(config[:managed_host], lpar)
            hash_profile[config[:managed_host]].insert(-1, hash_lpar[config[:managed_host]][0])
          end
        when "all"
          array_hosts = getmanagedsys
          array_hosts.each do |sys|
            hash_profile[sys] = Array.new
            array_lpars = getlparlist(sys)
            array_lpars.each do |lpar|
              hash_lpar =  getlparconfig(sys, lpar)
              hash_profile[sys].insert(-1, hash_lpar[sys][0])
            end
          end
        end
        return hash_profile
      end
    end
  end
end
