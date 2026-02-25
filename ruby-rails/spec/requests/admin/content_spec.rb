require "rails_helper"

RSpec.describe "Admin::Content", type: :request do
  describe "GET /admin/content" do
    context "when there are no nodes" do
      it "returns 200 and shows the empty state" do
        get "/admin/content"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No content yet.")
      end
    end

    context "when nodes exist" do
      let!(:older_node) do
        Node.create!(title: "Older Post", body: "Older body", published: true)
      end

      let!(:newer_node) do
        Node.create!(title: "Newer Post", body: "Newer body", published: false)
      end

      it "returns 200 and displays a table" do
        get "/admin/content"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("<table>")
      end

      it "displays the correct column headers" do
        get "/admin/content"

        expect(response.body).to include("<th scope=\"col\">Title</th>")
        expect(response.body).to include("<th scope=\"col\">Slug</th>")
        expect(response.body).to include("<th scope=\"col\">Status</th>")
        expect(response.body).to include("<th scope=\"col\">Updated</th>")
      end

      it "orders nodes by updated_at descending" do
        get "/admin/content"

        newer_pos = response.body.index("Newer Post")
        older_pos = response.body.index("Older Post")
        expect(newer_pos).to be < older_pos
      end

      it "links each title to its show page" do
        get "/admin/content"

        expect(response.body).to include("href=\"/admin/content/#{newer_node.id}\"")
        expect(response.body).to include("href=\"/admin/content/#{older_node.id}\"")
      end

      it "displays the correct status text" do
        get "/admin/content"

        expect(response.body).to include("Published")
        expect(response.body).to include("Draft")
      end
    end

    it "includes a 'New Node' link pointing to /admin/content/new" do
      get "/admin/content"

      expect(response.body).to include("New Node")
      expect(response.body).to include("href=\"/admin/content/new\"")
    end
  end

  describe "GET /admin/content/:id" do
    let!(:node) do
      Node.create!(
        title: "Test Node",
        body: "Some <strong>bold</strong> content",
        published: true
      )
    end

    it "returns 200 and shows the node title" do
      get "/admin/content/#{node.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h1>Test Node</h1>")
    end

    it "displays the node details" do
      get "/admin/content/#{node.id}"

      expect(response.body).to include("test-node")
      expect(response.body).to include("Published")
    end

    it "escapes HTML in the body" do
      get "/admin/content/#{node.id}"

      expect(response.body).to include("&lt;strong&gt;bold&lt;/strong&gt;")
      expect(response.body).not_to include("<strong>bold</strong>")
    end

    it "includes a 'Back to content' link to /admin/content" do
      get "/admin/content/#{node.id}"

      expect(response.body).to include("Back to content")
      expect(response.body).to include("href=\"/admin/content\"")
    end

    it "includes an 'Edit' link to the edit page" do
      get "/admin/content/#{node.id}"

      expect(response.body).to include("Edit")
      expect(response.body).to include("href=\"/admin/content/#{node.id}/edit\"")
    end

    it "returns 404 for a non-existent ID" do
      get "/admin/content/999999"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a non-integer ID" do
      get "/admin/content/abc"

      expect(response).to have_http_status(:not_found)
    end
  end
end
