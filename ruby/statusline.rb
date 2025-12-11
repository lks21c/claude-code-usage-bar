#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'date'
require 'set'

# DEBUG with
# echo '{"workspace": {"current_dir": "/Users/gdehan/.claude/utils/local-tts"}, "model": {"display_name": "Claude 4.1 Opus"}, "session_id": "test"}' | env CLAUDE_STATUS_DISPLAY_MODE=text CLAUDE_STATUS_PLAN=pro CLAUDE_STATUS_INFO_MODE=text ruby ./statusline.rb

# Claude Code Status Line - Clean, minimal, and precise
# Matches Claude Monitor's token calculation logic exactly
#
# Environment Variables:
#   CLAUDE_STATUS_DISPLAY_MODE - Display style: minimal, colors (default), or background
#   CLAUDE_STATUS_PLAN        - Plan type: pro, max5, max20, custom (defaults to 'max5')
#   CLAUDE_STATUS_INFO_MODE   - Info display: none (default), emoji, or text
class ClaudeStatusLine
  # Configuration
  DEFAULT_DISPLAY_MODE = :colors
  DEFAULT_INFO_MODE = :none

  # Constants
  SESSION_DURATION_HOURS = 5

  # Emoji mappings for info mode
  EMOJIS = {
    directory: "📁",
    git: "🔀",
    model: "🦾",
    tokens: "📓",
    messages: "✏️",
    time: "⏱️"
  }.freeze

  # Plan limits mapping (from Claude Monitor's plans.py)
  PLAN_LIMITS = {
    'pro' => { tokens: 19_000, messages: 250 },         # Pro plan
    'max5' => { tokens: 88_000, messages: 1_000 },      # Max5 plan
    'max20' => { tokens: 220_000, messages: 2_000 },    # Max20 plan
    'custom' => { tokens: 44_000, messages: 250 },      # Custom plan

    # Aliases and variations
    'max' => { tokens: 88_000, messages: 1_000 },       # Alias for max5
  }.freeze

  def self.detect_plan
    # Check environment variables first (multiple options for flexibility)
    plan_from_env = ENV['CLAUDE_STATUS_PLAN'] || ENV['CLAUDE_PLAN'] || ENV['CLAUDE_CODE_PLAN']
    return plan_from_env if plan_from_env && PLAN_LIMITS.key?(plan_from_env)

    # Check settings.json
    settings_file = File.expand_path('~/.claude/settings.json')
    if File.exist?(settings_file)
      begin
        settings = JSON.parse(File.read(settings_file))
        plan_from_settings = settings['model']
        return plan_from_settings if plan_from_settings && PLAN_LIMITS.key?(plan_from_settings)
      rescue JSON::ParserError, Errno::ENOENT
        # Continue to fallback
      end
    end

    'max' # Default to max plan
  end

  def self.get_limits(plan = nil)
    plan ||= detect_plan
    PLAN_LIMITS[plan] || PLAN_LIMITS['max']
  end

  # Color schemes
  COLOR_SCHEMES = {
    colors: {
      directory: "\033[38;5;51m",    # Soft sky blue
      model: "\033[38;5;105m",        # Soft pink/magenta
      tokens: "\033[38;5;141m",       # Soft cyan
      messages: "\033[38;5;147m",     # Soft green
      time: "\033[38;5;220m",         # Soft yellow
      git_clean: "\033[38;5;154m",    # Soft green
      git_dirty: "\033[38;5;222m",    # Soft peach/orange
      gray: "\033[90m",
      reset: "\033[0m"
    },
    minimal: {
      directory: "\033[38;5;250m",
      model: "\033[38;5;248m",
      tokens: "\033[38;5;248m",
      messages: "\033[38;5;248m",
      time: "\033[38;5;248m",
      git_clean: "\033[38;5;248m",
      git_dirty: "\033[38;5;248m",
      gray: "\033[90m",
      reset: "\033[0m"
    },
    background: {
      directory: "\033[44m\033[37m",     # Blue bg, white text
      model: "\033[45m\033[37m",         # Magenta bg, white text
      tokens: "\033[46m\033[30m",        # Cyan bg, black text
      messages: "\033[42m\033[30m",      # Green bg, black text
      time: "\033[43m\033[30m",          # Yellow bg, black text
      git_clean: "\033[42m\033[37m",           # Bold green
      git_dirty: "\033[43m\033[37m",           # Bold yellow
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

    # Auto-detect plan and set limits
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

  def usage_parts
    usage = calculate_usage
    [
      colorize(usage[:tokens], :tokens),
      colorize(usage[:messages], :messages),
      colorize(usage[:reset_time], :time)
    ]
  end

  def usage_parts_with_padding
    usage = calculate_usage
    [
      colorize(" #{usage[:tokens]} ", :tokens),
      colorize(" #{usage[:messages]} ", :messages),
      colorize(" #{usage[:reset_time]} ", :time)
    ]
  end

  def usage_parts_with_info
    usage = calculate_usage
    [
      format_with_info(usage[:tokens], :tokens),
      format_with_info(usage[:messages], :messages),
      format_with_info(usage[:reset_time], :time)
    ]
  end

  def usage_parts_with_padding_and_info
    usage = calculate_usage
    [
      format_with_info_and_padding(usage[:tokens], :tokens),
      format_with_info_and_padding(usage[:messages], :messages),
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
    when :tokens
      " tokens"
    when :messages
      " messages"
    when :time
      " before reset"
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
      # No text suffix for git info as requested
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

    blocks = create_session_blocks(entries)
    current_block = find_active_block(blocks)
    return default_usage unless current_block

    format_usage_data(current_block)
  end

  def load_usage_entries
    project_dir = File.expand_path('~/.claude/projects')
    return [] unless Dir.exist?(project_dir)

    cutoff_time = Time.now - (96 * 3600) # 4 days like Claude Monitor
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
    # Time filtering
    timestamp = parse_timestamp(data['timestamp'])
    return nil unless timestamp && timestamp >= cutoff_time

    # Deduplication
    hash = unique_hash(data)
    if hash && processed_hashes.include?(hash)
      return nil
    end

    # Token extraction and validation
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

      if input > 0 || output > 0
        tokens.merge!({
          input_tokens: input,
          output_tokens: output,
          cache_creation_tokens: cache_creation,
          cache_read_tokens: cache_read,
          total_tokens: input + output
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

  def create_session_blocks(entries)
    return [] if entries.empty?

    blocks = []
    current_block = nil

    entries.each do |timestamp, tokens|
      if new_block_needed?(current_block, timestamp)
        blocks << current_block if current_block
        current_block = new_session_block(timestamp)
      end

      add_to_block(current_block, timestamp, tokens)
    end

    blocks << current_block if current_block
    blocks
  end

  def new_block_needed?(current_block, timestamp)
    return true unless current_block

    timestamp >= current_block[:end_time] ||
      (current_block[:last_timestamp] &&
       (timestamp - current_block[:last_timestamp]) >= SESSION_DURATION_HOURS * 3600)
  end

  def new_session_block(timestamp)
    start_time = round_to_hour(timestamp)
    {
      start_time: start_time,
      end_time: start_time + (SESSION_DURATION_HOURS * 3600),
      total_tokens: 0,
      message_count: 0,
      first_timestamp: timestamp,
      last_timestamp: nil
    }
  end

  def add_to_block(block, timestamp, tokens)
    return unless timestamp >= block[:start_time] && timestamp < block[:end_time]

    block[:total_tokens] += tokens
    block[:message_count] += 1
    block[:last_timestamp] = timestamp
  end

  def round_to_hour(timestamp)
    utc = timestamp.utc
    Time.new(utc.year, utc.month, utc.day, utc.hour, 0, 0, 0)
  end

  def find_active_block(blocks)
    current_time = Time.now

    # Mark active blocks
    blocks.each { |block| block[:is_active] = block[:end_time] > current_time }

    # Return first active block (Claude Monitor logic)
    blocks.find { |block| block[:is_active] } ||
      blocks.max_by { |block| block[:last_timestamp] || block[:first_timestamp] }
  end

  def format_usage_data(block)
    reset_time_local = block[:end_time].localtime
    reset_display = reset_time_local.strftime("%H:%M")

    {
      tokens: format_count(block[:total_tokens], @limits[:tokens]),
      messages: "#{block[:message_count]}/#{@limits[:messages]}".strip,
      reset_time: "→#{reset_display}"
    }
  end

  def format_count(current, limit)
    percentage = limit > 0 ? ((current.to_f / limit) * 100).round(1) : 0
    "#{percentage}%"
  end

  def default_usage
    default_reset = (Time.now + 5 * 3600).localtime.strftime("%H:%M")
    {
      tokens: "0%",
      messages: "0/1000",
      reset_time: "→#{default_reset}"
    }
  end
end

# Execute
puts ClaudeStatusLine.new.generate
