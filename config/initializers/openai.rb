OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_API_KEY")
  config.uri_base = "https://api.groq.com/openai"
end
