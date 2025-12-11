#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'date'
require 'set'

# Claude Code Status Line - Daily and Weekly Token Usage
#
# Environment Variables:
#   CLAUDE_STATUS_DISPLAY_MODE - Display style: minimal, colors (default), or background
#   CLAUDE_STATUS_PLAN        - Plan type: pro, max5, max20, custom (defaults to 'max5')
#   CLAUDE_STATUS_INFO_MODE   - Info display: none (default), emoji, or text
class ClaudeStatusLine
  # Configuration
  DEFAULT_DISPLAY_MODE = :colors
  DEFAULT_INFO_MODE = :none

  # Emoji mappings for info mode
  EMOJIS = {
    directory: "📁",
    git: "🔀",
    model: "🦾",
    daily: "",
    weekly: "",
    time: ""
  }.freeze

  # Plan limits mapping - daily token limits
  PLAN_LIMITS = {
    'pro' => { daily_tokens: 45_000_000 },
    'max5' => { daily_tokens: 225_000_000 },
    'max20' => { daily_tokens: 900_000_000 },
    'custom' => { daily_tokens: 45_000_000 },
    'max' => { daily_tokens: 225_000_000 },
  }.freeze

  def self.detect_plan
    plan_from_env = ENV['CLAUDE_STATUS_PLAN'] || ENV['CLAUDE_PLAN'] || ENV['CLAUDE_CODE_PLAN']
    return plan_from_env if plan_from_env && PLAN_LIMITS.key?(plan_from_env)

    settings_file = File.expand_path('~/.claude/settings.json')
    if File.exist?(settings_file)
      begin
        settings = JSON.parse(File.read(settings_file))
        plan_from_settings = settings['model']
        return plan_from_settings if plan_from_settings && PLAN_LIMITS.key?(plan_from_settings)
      rescue JSON::ParserError, Errno::ENOENT
      end
    end

    'max5'
  end

  def self.get_limits(plan = nil)
    plan ||= detect_plan
    PLAN_LIMITS[plan] || PLAN_LIMITS['max5']
  end

  # Color schemes
  COLOR_SCHEMES = {
    colors: {
      directory: "\033[38;5;51m",
      model: "\033[38;5;105m",
      daily: "\033[38;5;141m",
      weekly: "\033[38;5;147m",
      time: "\033[38;5;220m",
      git_clean: "\033[38;5;154m",
      git_dirty: "\033[38;5;222m",
      gray: "\033[90m",
      reset: "\033[0m"
    },
    minimal: {
      directory: "\033[38;5;250m",
      model: "\033[38;5;248m",
      daily: "\033[38;5;248m",
      weekly: "\033[38;5;248m",
      time: "\033[38;5;248m",
      git_clean: "\033[38;5;248m",
      git_dirty: "\033[38;5;248m",
      gray: "\033[90m",
      reset: "\033[0m"
    },
    background: {
      directory: "\033[44m\033[37m",
      model: "\033[45m\033[37m",
      daily: "\033[46m\033[30m",
      weekly: "\033[42m\033[30m",
      time: "\033[43m\033[30m",
      git_clean: "\033[42m\033[37m",
      git_dirty: "\033[43m\033[37m",
      gray: "\033[90m",
      reset: "\033[0m"
    }
  }.freeze

  def initialize
    @input_data = JSON.parse($stdin.read)
    @current_dir = @input_data.dig('workspace', 'current_dir') || @input_data['cwd']
    @model_name = @input_data.dig('model', 'display_name')
    @dir_name = File.basename(@current_dir) if @current_dir
    @display_mode = (ENV['CLAUDE_STATUS_DISPLAY_MODE']&.to_sym || DEFAULT_DISPLAY_MODE)
    @info_mode = (ENV['CLAUDE_STATUS_INFO_MODE']&.to_sym || DEFAULT_INFO_MODE)
    @colors = COLOR_SCHEMES[@display_mode] || COLOR_SCHEMES[DEFAULT_DISPLAY_MODE]

    @plan = self.class.detect_plan
    @limits = self.class.get_limits(@plan)
  end

  def generate
    parts = build_status_parts
    join_parts(parts)
  end

  private

  def build_status_parts
    if @display_mode == :background
      [
        format_with_info(" #{@dir_name} ", :directory),
        git_info_colored_with_info,
        format_with_info(" #{@model_name} ", :model),
        *usage_parts_with_padding_and_info
      ].compact
    else
      [
        format_with_info("#{@dir_name}/", :directory),
        git_info_colored_with_info,
        format_with_info(@model_name, :model),
        *usage_parts_with_info
      ].compact
    end
  end

  def usage_parts_with_info
    usage = calculate_usage
    [
      format_with_info(usage[:daily], :daily),
      format_with_info(usage[:weekly], :weekly),
      format_with_info(usage[:reset_time], :time)
    ]
  end

  def usage_parts_with_padding_and_info
    usage = calculate_usage
    [
      format_with_info_and_padding(usage[:daily], :daily),
      format_with_info_and_padding(usage[:weekly], :weekly),
      format_with_info_and_padding(usage[:reset_time], :time)
    ]
  end

  def join_parts(parts)
    if @display_mode == :background
      parts.join(' ')
    else
      separator = "#{@colors[:gray]}·#{@colors[:reset]}"
      parts.join(" #{separator} ")
    end
  end

  def colorize(text, color)
    return '' unless text
    "#{@colors[color]}#{text}#{@colors[:reset]}"
  end

  def format_with_info(text, type)
    return colorize(text, type) unless text

    case @info_mode
    when :emoji
      emoji = EMOJIS[type]
      if @display_mode == :background
        colorize("#{emoji}#{text} ", type)
      else
        colorize("#{emoji} #{text} ", type)
      end
    when :text
      suffix = get_text_suffix(type)
      colorize("#{text}#{suffix}", type)
    else
      colorize(text, type)
    end
  end

  def format_with_info_and_padding(text, type)
    return colorize(" #{text} ", type) unless text

    case @info_mode
    when :emoji
      emoji = EMOJIS[type]
      colorize("#{emoji} #{text} ", type)
    when :text
      suffix = get_text_suffix(type)
      colorize(" #{text}#{suffix} ", type)
    else
      colorize(" #{text} ", type)
    end
  end

  def get_text_suffix(type)
    case type
    when :daily
      " daily"
    when :weekly
      " weekly"
    when :time
      " reset"
    else
      ""
    end
  end

  def git_info_colored_with_info
    info = git_info
    return nil unless info

    color = info.match?(/[?+!↑↓]/) ? :git_dirty : :git_clean

    case @info_mode
    when :emoji
      emoji = EMOJIS[:git]
      if @display_mode == :background
        colorize("#{emoji}#{info} ", color)
      else
        colorize("#{emoji} #{info}", color)
      end
    else
      if @display_mode == :background
        colorize("#{info} ", color)
      else
        colorize(info, color)
      end
    end
  end

  def git_info
    return nil unless @current_dir && Dir.exist?(File.join(@current_dir, '.git'))

    Dir.chdir(@current_dir) do
      branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
      return nil if branch.empty?

      indicators = build_git_indicators
      " #{branch}#{indicators}"
    end
  rescue
    nil
  end

  def build_git_indicators
    status = `git status --porcelain 2>/dev/null`.strip
    branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
    ahead_behind = `git rev-list --left-right --count origin/#{branch}...#{branch} 2>/dev/null`.strip

    indicators = ''
    indicators += '?' if status.match?(/^\?\?/)
    indicators += '+' if status.match?(/^[AM]/)
    indicators += '!' if status.match?(/^[MD]/)

    if ahead_behind.match(/^(\d+)\s+(\d+)$/)
      behind, ahead = ahead_behind.split.map(&:to_i)
      indicators += "↑#{ahead}" if ahead > 0
      indicators += "↓#{behind}" if behind > 0
    end

    indicators
  end

  def calculate_usage
    entries = load_usage_entries
    return default_usage if entries.empty?

    now = Time.now

    # Calculate daily tokens (last 24 hours)
    day_ago = now - (24 * 3600)
    daily_tokens = entries.select { |ts, _| ts >= day_ago }.sum { |_, tokens| tokens }

    # Calculate weekly tokens (last 7 days)
    week_ago = now - (7 * 24 * 3600)
    weekly_tokens = entries.select { |ts, _| ts >= week_ago }.sum { |_, tokens| tokens }

    daily_limit = @limits[:daily_tokens]
    weekly_limit = daily_limit * 7

    daily_pct = ((daily_tokens.to_f / daily_limit) * 100).round(1)
    weekly_pct = ((weekly_tokens.to_f / weekly_limit) * 100).round(1)

    {
      daily: "D:#{daily_pct}%",
      weekly: "W:#{weekly_pct}%",
      reset_time: "@00:00"
    }
  end

  def load_usage_entries
    project_dir = File.expand_path('~/.claude/projects')
    return [] unless Dir.exist?(project_dir)

    cutoff_time = Time.now - (8 * 24 * 3600) # 8 days for weekly calculation
    processed_hashes = Set.new
    entries = []

    Dir.glob(File.join(project_dir, "**/*.jsonl")).each do |file|
      entries.concat(parse_jsonl_file(file, cutoff_time, processed_hashes))
    end

    entries.sort_by!(&:first)
  end

  def parse_jsonl_file(file, cutoff_time, processed_hashes)
    entries = []

    File.foreach(file) do |line|
      next if line.strip.empty?

      begin
        data = JSON.parse(line)
        entry = process_jsonl_entry(data, cutoff_time, processed_hashes)
        entries << entry if entry
      rescue JSON::ParserError, ArgumentError
        next
      end
    end

    entries
  end

  def process_jsonl_entry(data, cutoff_time, processed_hashes)
    timestamp = parse_timestamp(data['timestamp'])
    return nil unless timestamp && timestamp >= cutoff_time

    hash = unique_hash(data)
    return nil if hash && processed_hashes.include?(hash)

    tokens = extract_tokens(data)
    individual_tokens = tokens.reject { |k, _| k == :total_tokens }
    return nil if individual_tokens.values.all? { |v| v <= 0 }

    processed_hashes.add(hash) if hash
    [timestamp, tokens[:total_tokens]]
  end

  def parse_timestamp(timestamp_str)
    return nil unless timestamp_str
    DateTime.parse(timestamp_str).to_time
  rescue ArgumentError
    nil
  end

  def unique_hash(data)
    message_id = data['message_id'] || data.dig('message', 'id')
    request_id = data['requestId'] || data['request_id']
    "#{message_id}:#{request_id}" if message_id && request_id
  end

  def extract_tokens(data)
    tokens = { input_tokens: 0, output_tokens: 0, cache_creation_tokens: 0, cache_read_tokens: 0, total_tokens: 0 }

    sources = token_sources(data)

    sources.each do |source|
      next unless source.is_a?(Hash)

      input = extract_token_field(source, %w[input_tokens inputTokens prompt_tokens])
      output = extract_token_field(source, %w[output_tokens outputTokens completion_tokens])
      cache_creation = extract_token_field(source, %w[cache_creation_tokens cache_creation_input_tokens cacheCreationInputTokens])
      cache_read = extract_token_field(source, %w[cache_read_input_tokens cache_read_tokens cacheReadInputTokens])

      if input > 0 || output > 0 || cache_creation > 0 || cache_read > 0
        # Total tokens should include cache tokens as they count towards usage limits
        total = input + output + cache_creation + cache_read
        tokens.merge!({
          input_tokens: input,
          output_tokens: output,
          cache_creation_tokens: cache_creation,
          cache_read_tokens: cache_read,
          total_tokens: total
        })
        break
      end
    end

    tokens
  end

  def token_sources(data)
    sources = []
    is_assistant = data['type'] == 'assistant'

    if is_assistant
      sources << data.dig('message', 'usage') if data.dig('message', 'usage').is_a?(Hash)
      sources << data['usage'] if data['usage'].is_a?(Hash)
    else
      sources << data['usage'] if data['usage'].is_a?(Hash)
      sources << data.dig('message', 'usage') if data.dig('message', 'usage').is_a?(Hash)
    end

    sources << data
    sources.compact
  end

  def extract_token_field(source, field_names)
    field_names.each do |field|
      value = source[field]
      return value.to_i if value && value > 0
    end
    0
  end

  def default_usage
    tomorrow = Date.today + 1
    reset_time = Time.new(tomorrow.year, tomorrow.month, tomorrow.day, 0, 0, 0)
    {
      daily: "D:0%",
      weekly: "W:0%",
      reset_time: "→#{reset_time.strftime("%H:%M")}"
    }
  end
end

# Execute
puts ClaudeStatusLine.new.generate
