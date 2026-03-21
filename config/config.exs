import Config

config :llm_db,
  compile_embed: true,
  integrity_policy: :strict

# Z.ai Anthropic-compatible endpoint for GLM Coding Plan subscribers
# Set ANTHROPIC_API_KEY to your Z.ai API key to use anthropic:glm-4.7 etc.
config :req_llm, :anthropic,
  base_url: System.get_env("ANTHROPIC_BASE_URL", "https://api.anthropic.com")
