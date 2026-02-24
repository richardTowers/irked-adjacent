require "rails_helper"

RSpec.describe "Hello", type: :request do
  describe "GET /hello" do
    it "returns hello world" do
      get "/hello"

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("Hello, world!")
    end
  end
end
