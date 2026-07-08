class ShiftGenerator
  API_URL = "https://api.groq.com/openai/v1/chat/completions".freeze
  MODEL = "llama-3.3-70b-versatile".freeze

  def initialize(prompt_builder)
    @prompt_builder = prompt_builder
  end

  def generate
    uri = URI(API_URL)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{ENV.fetch('OPENAI_API_KEY')}"
    request.body = {
      model: MODEL,
      messages: [
        { role: "system", content: @prompt_builder.system_prompt },
        { role: "user", content: @prompt_builder.user_prompt }
      ],
      temperature: 0.2
    }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.read_timeout = 60
      http.request(request)
    end

    body = JSON.parse(response.body)

    if response.code == "200"
      content = body.dig("choices", 0, "message", "content")
      { success: true, content: content }
    else
      { success: false, error: "APIエラーが発生しました（#{response.code}）: #{body.dig('error', 'message')}" }
    end
  rescue Net::ReadTimeout
    { success: false, error: "APIへの接続がタイムアウトしました。しばらく待ってから再試行してください。" }
  rescue StandardError => e
    { success: false, error: "予期しないエラーが発生しました: #{e.message}" }
  end
end
