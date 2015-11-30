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
require 'powervmtools'
require 'chef/knife/power_common'
require 'pp'

class Chef
  class Knife
    class PowerMappingGet < Knife
      include Chef::Knife::PowerCommon
      ###
      ### Set of tools to lpar configuration
      ### => used to get hdisk : vio : adapter : vscsi mappings
      ###
      banner "knife power mapping get [options]"

      option :configfile,
        :short => "-C configfile",
        :long => "--config-file configfile",
        :description => "optional configuration to use",
        :default => "~/knife-power-config.yml"

      option :managed_host,
        :short => "-m MANAGED_HOST",
        :long => "--managed-host MANAGED_HOST",
        :description => "Managed Host Name"

      option :partition,
        :short => "-n PARTITION",
        :long => "--partition PARTITION",
        :description => "Partition Name"

      option :output_format,
        :short => "-o FORMAT (csv)",
        :long => "--export-format FORMAT (csv|json)",
        :description => "output format for specified format"

      option :debug,
        :long => "--debug",
        :description => "set the debug flag"

      #
      # Run the plugin
      #

      def run
        check_params
        #hash_mapping = getconfig
        #### creating the HMC object
        if config[:debug]
          debug = true
        else
          debug = false
        end
        @myhmc = PowerVMTools::HMC.new(config[:hmc],{ :user => config[:hmc_user], :passwd => config[:hmcpasswd], :port => config[:ssh_port],:debug => debug })
        @myframe = PowerVMTools::Frame.new(config[:managed_host],@myhmc)
        check_frame_lpar
        mylpar = PowerVMTools::Lpar.new(config[:partition],{:frame => @myframe })
        hash_mappings = Hash.new
        hash_mappings["vscsi"] = mylpar.getmappings
        hash_mappings["vfc"] = mylpar.getvfcmappings
        if config[:output_format] == "csv"
          print_mapping_csv(hash_mappings)
        elsif config[:output_format] == "json"
          print_mapping_json(hash_mappings)
        else
          print_mapping(hash_mappings)
        end
      end
      def check_frame_lpar
        ## check if frame exists
        if not @myhmc.framesbystatus("Operating").include?(config[:managed_host])
         ui.error "Frame #{config[:managed_host]} does not exists or is not in a proper state"
         exit 1
        end
        @myframe = PowerVMTools::Frame.new(config[:managed_host],@myhmc)
        if not @myframe.lpars.include?(config[:partition])
          ui.error "Lpar #{config[:partition]} does not exists on this Frame"
          exit 1
        end
      end

      def check_params
        initsettings()
        if config[:hmc].nil?
          ui.error "No HMC parameter specified in configuration file"
          exit 1
        end
        if config[:managed_host].nil?
          ui.error "No frame specified. Add one with '-m framename'"
          show_usage
          exit 1
        end
        if config[:partition].nil?
          ui.error "No partition specified. Add one with '-n partitionname'"
          show_usage
          exit 1
        end
        ui.info "Will fetch partition #{ui.color(config[:partition], :cyan)} from managed host #{ui.color(config[:managed_host], :cyan)} on hmc #{ui.color(config[:hmc], :cyan)}"
      end

      def export_config(hash_profile,directory)
        hash_profile.each do |sys,array|
          array.each do |profile|
            fullpath = directory + sys + "_" + profile["lpar_name"] + "_" + profile["name"] + ".json"
            savejson(profile,fullpath)
          end
        end
      end
      def print_mapping_json(hash_mapping)
        puts hash_mapping.to_json
      end
      def print_mapping_csv(hash_mapping)
        ui.info "Managed system : #{ui.color(config[:managed_host], :cyan)} \t Partition : #{ui.color(config[:partition], :cyan)}"
	if not hash_mapping['vscsi'].nil?
          ui.info "LPAR;ViosID;SrvAdapID;vhost;CltAdapID;device;lun;vtd;pvid;ArraySN;DevID;Size"
          hash_mapping['vscsi'].each do |item|
            item[:mappings].each do |mapping|
              print "#{config[:partition]};#{item[:vioserverid].to_s};#{item[:serveradapterid].to_s};#{item[:devname]};#{item[:clientadapterid].to_s};"
              print "#{mapping["vtd"].chomp};#{mapping["lun"].chomp};#{mapping["backingdevice"].chomp};#{mapping["pvid"].chomp};#{mapping["sernum"]};\"#{mapping["devid"]}\";#{mapping["size"]}\n"
	    end	
          end
	end
        if not hash_mapping['vfc'].nil?
          ui.info "ViosID;SrvAdapID;vfchost;CltAdapID;PhysLoc;VioDev;ClntDev;WWN1;WWN2;Flags;Ports LoggedIn"
          hash_mapping['vfc'].each do |item|
            print "#{item["vios"].to_s};#{item["serveradapterid"].to_s};#{item["vfchost"]};#{item["clientadapterid"].to_s};#{item["fcmap"]["physloc"]};#{item["fcmap"]["fcname"]};"
            print "#{item["fcmap"]["clntfcname"]};#{item["wwn1"]};#{item["wwn2"]};"
            if item["fcmap"]["flags"] == "a"
              print "<LOGGED_IN,STRIP_MERGE>;"
            elsif item["fcmap"]["flags"] == "1"
              print "<NOT_MAPPED,NOT_CONNECTED>;"
            else
              print "#{item["fcmap"]["flags"]};"
            end
            print "#{item["fcmap"]["portstatus"]}\n"
          end
        end
      end

      def print_mapping(hash_mapping)
        configfile = loadConfig(File.expand_path(config[:configfile]))
        ui.info "Managed system : #{ui.color(config[:managed_host], :cyan)} \t Partition : #{ui.color(config[:partition], :cyan)}"
        if not hash_mapping["vscsi"].nil?
          adapter_list = [
            ui.color('ViosID', :cyan),
            ui.color('SrvAdapID', :cyan),
            ui.color('vhost', :cyan),
            ui.color('CltAdapID', :cyan),
            ui.color('device', :cyan),
            ui.color('lun', :cyan),
            ui.color('vtd', :cyan),
            ui.color('pvid', :cyan),
            ui.color('ArraySN', :cyan),
            ui.color('DevID', :cyan),
            ui.color('Size', :cyan),
          ].flatten.compact
          colcount = adapter_list.length
          hash_mapping["vscsi"].each do |item|
            adapter_list << item[:vioserverid].to_s
            adapter_list << item[:serveradapterid].to_s
            adapter_list << item[:devname]
            adapter_list << item[:clientadapterid].to_s
            first = 1
            if item[:mappings].length > 0
              sorted = item[:mappings].sort_by { |k| k['lun'] }
              sorted.each do |mapping|
                if first == 1
                  adapter_list << mapping["vtd"].chomp
                  adapter_list << mapping["lun"].chomp
                  adapter_list << mapping["backingdevice"].chomp
                  adapter_list << mapping["pvid"].chomp
                  ## try to map friendly names for this sernum
                  if configfile[:friendlynames][:storagearray][mapping["sernum"]]
                    adapter_list << configfile[:friendlynames][:storagearray][mapping["sernum"]]
                  else
                    adapter_list << mapping["sernum"]
                  end
                  adapter_list << mapping["devid"]
                  adapter_list << mapping["size"]
                  first += 1
                else
                  adapter_list << " "
                  adapter_list << " "
                  adapter_list << " "
                  adapter_list << " "
                  adapter_list << mapping["vtd"].chomp
                  adapter_list << mapping["lun"].chomp
                  adapter_list << mapping["backingdevice"].chomp
                  adapter_list << mapping["pvid"].chomp
                  ## try to map friendly names for this sernum
                  if configfile[:friendlynames][:storagearray][mapping["sernum"]]
                    adapter_list << configfile[:friendlynames][:storagearray][mapping["sernum"]]
                  else
                    adapter_list << mapping["sernum"]
                  end
                  adapter_list << mapping["devid"]
                  adapter_list << mapping["size"]
                end
              end
            else
              adapter_list << " "
              adapter_list << " "
              adapter_list << " "
              adapter_list << " "
              adapter_list << " "
              adapter_list << " "
              adapter_list << " "
              first = 1
            end
          end
          puts ui.list(adapter_list, :uneven_columns_across, colcount)
          ui.info "\n"
        end
        if not hash_mapping['vfc'].nil?
          vfc_list = [
            ui.color('ViosID', :cyan),
            ui.color('SrvAdapID', :cyan),
            ui.color('vfchost', :cyan),
            ui.color('CltAdapID', :cyan),
            ui.color('PhysLoc', :cyan),
            ui.color('VioDev', :cyan),
            ui.color('ClntDev', :cyan),
            ui.color('WWN1', :cyan),
            ui.color('WWN2', :cyan),
            ui.color('Status', :cyan),
            ui.color('flags', :cyan),
            ui.color('Ports LoggedIn', :cyan),
          ].flatten.compact
          colcount2 = vfc_list.length
          hash_mapping['vfc'].each do |item|
            vfc_list << item[:vioserverid].to_s
            vfc_list << item[:serveradapterid].to_s
            vfc_list << item[:devname]
            vfc_list << item[:clientadapterid].to_s
            vfc_list << item[:fcmap]["physloc"]
            vfc_list << item[:fcmap]["fcname"]
            vfc_list << item[:fcmap]["clntfcname"]
            vfc_list << item[:wwn1]
            vfc_list << item[:wwn2]
            vfc_list << item[:fcmap]["status"].to_s
            if item[:fcmap]["flags"] == "a"
              vfc_list << "<LOGGED_IN,STRIP_MERGE>"
            elsif item[:fcmap]["flags"] == "1"
              vfc_list << "<NOT_MAPPED,NOT_CONNECTED>"
            else
              vfc_list << item[:fcmap]["flags"]
            end
            vfc_list << item[:fcmap]["portstatus"]
          end
          puts ui.list(vfc_list, :uneven_columns_across, colcount2)
          ui.info "\n"
        end
      end
    end

#    def getconfig
#      hash = Hash.new
#      hash_mapping = Hash.new
#      hash_mapping['vscsi'] = Array.new
#      hash_mapping['vfc'] = Array.new
#      Net::SSH.start(config[:hmc], config[:hmc_user], {:password => @hmc_passwd,:port => config[:ssh_port]}) do |ssh|
#        command = "lssyscfg -r prof -m #{config[:managed_host]} --filter \"lpar_names=#{config[:partition]},profile_names=$(lssyscfg -r lpar -m #{config[:managed_host]} --filter \"lpar_names=#{config[:partition]}\" -F curr_profile)\""
#        output = run_remote_command(ssh, command)
#        if output =~ /The command entered has a malformed filter/
#          ui.info "Reverting do 'Default_Profile' as there is no 'curr_profile'"
#          command = "lssyscfg -r prof -m #{config[:managed_host]} --filter \"lpar_names=#{config[:partition]},profile_names=$(lssyscfg -r lpar -m #{config[:managed_host]} --filter \"lpar_names=#{config[:partition]}\" -F default_profile)\""
#          output = run_remote_command(ssh, command)
#        end
#        if output =~ /HSCL8/
#          ui.error "Error running the command"
#          output.split("\n").first(2).each do |x|
#            ui.error x
#            exit 1
##          end
#          ui.error "..."
#        end
#        profile = parse_profile(output)
#        hash[config[:managed_host]] = [profile]
#        profile["virtual_scsi_adapters"].split(",").each do |vscsi|
#          array_info = vscsi.split("/") ## spliting into a array the vscsi line
#          clientadapterid = array_info[0].to_i
#          serveradapterid = array_info[4].to_i
#          vioserverid = array_info[2].to_i
#          vscsiname = fetch_vio_vadapter(config[:managed_host],vioserverid,serveradapterid)
#          mappings = fetch_vio_maps(config[:managed_host],vioserverid,vscsiname)
#          hash_mapping['vscsi'].insert(-1, { "vios" => vioserverid, "vhost" => vscsiname, "serveradapterid" => serveradapterid, "clientadapterid" => clientadapterid, "mappings" => mappings})
#        end
#        if profile.has_key?("virtual_fc_adapters") and not profile["virtual_fc_adapters"] == "none"
#          profile["virtual_fc_adapters"].split(",").each do |vfc|
#            array_info = vfc.split("/") ## spliting into a array the vfc line
#            clientadapterid = array_info[0].to_i
#            serveradapterid = array_info[4].to_i
#            vioserverid = array_info[2].to_i
#            vfcname = fetch_vio_vadapter(config[:managed_host],vioserverid,serveradapterid)
#            fcmap = fetch_vio_fcmap(config[:managed_host],vioserverid,vfcname)
#            hash_mapping['vfc'].insert(-1, { "vios" => vioserverid, "vfchost" => vfcname, "serveradapterid" => serveradapterid, "clientadapterid" => clientadapterid, "wwn1" => array_info[5], "wwn2" => array_info[6], "fcmap" => fcmap })
#          end
#        end
#        return hash_mapping
#      end
#    end
  end
end

