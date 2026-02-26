require "rails_helper"

RSpec.describe "Public::Content", type: :request do
  let(:main_branch) { Branch.find_by!(name: "main") }

  def create_and_publish(title:, slug: nil, body: nil)
    node, version = Node.create_with_version(title: title, slug: slug, body: body)
    version.commit!("Initial commit")
    Version.publish!(version)
    node
  end

  describe "GET /:slug" do
    context "when the node is published" do
      let!(:node) { create_and_publish(title: "Hello World", body: "Welcome to the site") }

      it "returns 200 and displays the title in an h1" do
        get "/#{node.slug}"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("<h1>Hello World</h1>")
      end

      it "displays the body" do
        get "/#{node.slug}"

        expect(response.body).to include("Welcome to the site")
      end

      it "does not display admin controls" do
        get "/#{node.slug}"

        expect(response.body).not_to include("Edit Node")
        expect(response.body).not_to include("Delete Node")
        expect(response.body).not_to include("Publish")
        expect(response.body).not_to include("/admin/")
      end

      it "does not display version metadata" do
        get "/#{node.slug}"

        expect(response.body).not_to include("Commit")
        expect(response.body).not_to include("commit_message")
        expect(response.body).not_to include("branch")
      end

      it "uses a layout distinct from the admin interface" do
        get "/#{node.slug}"

        # Public layout should not have admin navigation
        expect(response.body).not_to include("Content</a>")
        expect(response.body).not_to include("simple.min.css")
      end

      it "has a meaningful title element" do
        get "/#{node.slug}"

        expect(response.body).to include("<title>Hello World</title>")
      end

      it "has a lang attribute on the html element" do
        get "/#{node.slug}"

        expect(response.body).to match(/<html[^>]*lang="en"/)
      end

      it "has a main element" do
        get "/#{node.slug}"

        expect(response.body).to include("<main>")
      end

      it "escapes HTML in the body" do
        node = create_and_publish(title: "XSS Test", body: "<script>alert('xss')</script>")

        get "/#{node.slug}"

        expect(response.body).to include("&lt;script&gt;")
        expect(response.body).not_to include("<script>alert")
      end
    end

    context "when the node exists but is not published" do
      it "returns 404" do
        node, _version = Node.create_with_version(title: "Unpublished Node")

        get "/#{node.slug}"

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when the slug does not exist" do
      it "returns 404" do
        get "/nonexistent-slug"

        expect(response).to have_http_status(:not_found)
      end
    end

    it "does not intercept admin routes" do
      get "/admin/content"

      expect(response).to have_http_status(:ok)
    end

    it "does not intercept /admin/content/new" do
      get "/admin/content/new"

      expect(response).to have_http_status(:ok)
    end
  end
end
