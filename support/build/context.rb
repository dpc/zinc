# Zinc, the bare metal stack for rust.
# Copyright 2014 Vladimir "farcaller" Pouzanov <farcaller@gmail.com>
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

require 'singleton'
require 'yaml'
require 'erb'

require 'build/board'
require 'build/platform'
require 'build/architecture'
require 'build/tracking_tasks'
require 'build/rlib'

class Context
  attr_reader :rules, :env, :application, :tracking_triple, :tracking_platform
  attr_reader :applications, :platform
  attr_accessor :platform

  def self.create(*args)
    raise RuntimeError("Context already created") if @context_instance
    @context_instance = new(*args)
  end

  def self.instance
    @context_instance
  end

  def initialize(rakefile, board)
    @cached_rlib_names = {}
    @rules = {}

    @root_path = File.dirname(rakefile)
    @available_boards = Board.from_yaml(root_dir('boards.yml'))
    @available_platforms = Platform.from_yaml(root_dir('platforms.yml'))
    @available_archs = Architecture.from_yaml(root_dir('architectures.yml'))

    @board = @available_boards[board] or raise ArgumentError.new(
        "Unknown board #{@board}, " +
        "available boards: #{@available_boards.keys.join(', ')}")
    @platform = @available_platforms[@board.platform] or raise ArgumentError.new(
        "Unknown platform #{@board.platform}, " +
        "available platforms: #{@available_platforms.keys.join(', ')}")
    @platform.arch = @available_archs[@platform.arch_name] or raise ArgumentError.new(
        "Undefined arch #{@platform.arch_name} for platform #{@platform}, " +
        "available architectures: #{@available_archs.keys.join(', ')}")

    collect_config_flags!
    collect_applications!
    initialize_environment!
    define_tracking_tasks!
  end

  # Returns path relative to root directory
  def root_dir(*args); File.join(@root_path, *args); end

  # Returns path relative to $root/src
  def src_dir(*args); File.join(root_dir, 'src', *args); end

  # Returns path relative to $root/build
  def build_dir(*args)
    path = File.join(root_dir, 'build', *args)
    directory = File.dirname(path)
    FileUtils.mkdir(directory) unless Dir.exists?(directory)
    path
  end

  # Returns path relative to $src/hal/$platform
  def platform_dir(*args); src_dir('hal', @platform.name, *args); end

  # Returns path relative to $build/intermediate
  def intermediate_dir(*args); build_dir('intermediate', *args); end

  # Returns rlib file name for given source file
  def rlib_name(src)
    unless @cached_rlib_names[src]
      @cached_rlib_names[src] = Rlib.crate_name(src)
    end

    @cached_rlib_names[src]
  end

  private
  def self.new(*args)
    super *args
  end

  def collect_config_flags!
    @config_flags = []
    @config_flags.concat @board.features.map { |f| "cfg_#{f}" }
    @config_flags.concat @platform.features.map { |f| "cfg_#{f}" }

    @config_flags << "board_#{@board.name}"
    @config_flags << "mcu_#{@platform.name}"
    @config_flags << "arch_#{@platform.arch.name}"

    @config_flags.map! do |c|
      "--cfg #{c}"
    end
  end

  def initialize_environment!
    @env = {}

    @env[:rustcflags_cross] = [
      "--target #{@platform.arch.target}",
      "-Ctarget-cpu=#{@platform.arch.cpu}",
      '-C relocation_model=static',
    ]

    @env[:rustcflags] = [
      '--opt-level 2',
      '-Z no-landing-pads',
    ] + @config_flags

    @env[:config_flags] = @config_flags

    @env[:cflags] = [
      '-mthumb',
      "-mcpu=#{@platform.arch.cpu}",
    ]

    @env[:ldflags] = [ %x( #{TOOLCHAIN}gcc -print-libgcc-file-name #{@env[:cflags].join(' ')}).chomp ]

    @env[:rustc] = env_const(:RUSTC)
    @env[:toolchain] = env_const(:TOOLCHAIN)
  end

  def define_tracking_tasks!
    @tracking_triple = TrackingTask.define_task(
        build_dir('.target_triple'), @platform.arch.target)
    @tracking_platform = TrackingTask.define_task(
        build_dir('.target_name'), @platform.name)
  end

  def collect_applications!
    @applications = FileList[root_dir('apps/app_*.rs')].map do |a|
      a.gsub(/^#{root_dir('apps')}\/app_(.+)\.rs/, '\1')
    end
  end

  def env_const(name)
    return ENV[name.to_s] if ENV[name.to_s]
    return Object.const_get(name) if Object.const_defined?(name)
    raise RuntimeError.new("Undefined constant #{name}")
  end
end
