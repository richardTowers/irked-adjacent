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

  describe "GET /admin/content/new" do
    it "returns 200 and renders the form" do
      get "/admin/content/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h1>New Node</h1>")
    end

    it "has form fields for title, slug, body, and published" do
      get "/admin/content/new"

      expect(response.body).to include("node[title]")
      expect(response.body).to include("node[slug]")
      expect(response.body).to include("node[body]")
      expect(response.body).to include("node[published]")
    end

    it "has a submit button labeled 'Create Node'" do
      get "/admin/content/new"

      expect(response.body).to include("Create Node")
    end

    it "has a cancel link to /admin/content" do
      get "/admin/content/new"

      expect(response.body).to include("Cancel")
      expect(response.body).to include("href=\"/admin/content\"")
    end

    it "marks the title field as required" do
      get "/admin/content/new"

      expect(response.body).to match(/required="required"[^>]*name="node\[title\]"/)
    end
  end

  describe "POST /admin/content" do
    context "with valid params" do
      it "creates a node and redirects to the show page" do
        expect {
          post "/admin/content", params: { node: { title: "My First Post", body: "Hello world" } }
        }.to change(Node, :count).by(1)

        node = Node.last
        expect(response).to redirect_to(admin_content_path(node))
      end

      it "shows a success flash message after redirect" do
        post "/admin/content", params: { node: { title: "My First Post" } }

        follow_redirect!

        expect(response.body).to include("Node was successfully created.")
      end

      it "has the flash message in an element with role='status'" do
        post "/admin/content", params: { node: { title: "Flash Test" } }

        follow_redirect!

        expect(response.body).to include('role="status"')
        expect(response.body).to include("Node was successfully created.")
      end
    end

    context "with blank title" do
      it "returns 422 and re-renders the form with errors" do
        post "/admin/content", params: { node: { title: "", body: "Some body" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("New Node")
        expect(response.body).to include("role=\"alert\"")
      end

      it "preserves previously entered values" do
        post "/admin/content", params: { node: { title: "", body: "Keep this body" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Keep this body")
      end

      it "marks the title field as aria-invalid" do
        post "/admin/content", params: { node: { title: "" } }

        expect(response.body).to include('aria-invalid="true"')
        expect(response.body).to include("title-error")
      end
    end

    context "slug handling" do
      it "auto-generates a slug from the title when slug is blank" do
        post "/admin/content", params: { node: { title: "My Great Post" } }

        node = Node.last
        expect(node.slug).to eq("my-great-post")
      end

      it "uses the provided slug when one is given" do
        post "/admin/content", params: { node: { title: "My Great Post", slug: "custom-slug" } }

        node = Node.last
        expect(node.slug).to eq("custom-slug")
      end

      it "returns 422 with error when slug is a duplicate" do
        Node.create!(title: "Existing", slug: "taken-slug")

        post "/admin/content", params: { node: { title: "New Post", slug: "taken-slug" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("slug-error")
      end
    end

    context "published flag" do
      it "sets published to true and records published_at when checked" do
        post "/admin/content", params: { node: { title: "Published Post", published: "1" } }

        node = Node.last
        expect(node.published).to be true
        expect(node.published_at).not_to be_nil
      end

      it "defaults to draft when published is not checked" do
        post "/admin/content", params: { node: { title: "Draft Post" } }

        node = Node.last
        expect(node.published).to be false
        expect(node.published_at).to be_nil
      end
    end

    context "strong parameters" do
      it "ignores unpermitted parameters" do
        post "/admin/content", params: { node: { title: "Safe Post", created_at: "2000-01-01" } }

        node = Node.last
        expect(node.title).to eq("Safe Post")
        expect(node.created_at).not_to eq(Time.zone.parse("2000-01-01"))
      end
    end
  end

  describe "GET /admin/content/:id/edit" do
    let!(:node) do
      Node.create!(title: "Editable Node", slug: "editable-node", body: "Original body", published: false)
    end

    it "returns 200 and displays the edit form" do
      get "/admin/content/#{node.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h1>Edit Node</h1>")
    end

    it "pre-fills the form with the node's current values" do
      get "/admin/content/#{node.id}/edit"

      expect(response.body).to include("Editable Node")
      expect(response.body).to include("editable-node")
      expect(response.body).to include("Original body")
    end

    it "has form fields for title, slug, body, and published" do
      get "/admin/content/#{node.id}/edit"

      expect(response.body).to include("node[title]")
      expect(response.body).to include("node[slug]")
      expect(response.body).to include("node[body]")
      expect(response.body).to include("node[published]")
    end

    it "has a submit button labeled 'Update Node'" do
      get "/admin/content/#{node.id}/edit"

      expect(response.body).to include("Update Node")
    end

    it "has a cancel link to the node's show page" do
      get "/admin/content/#{node.id}/edit"

      expect(response.body).to include("Cancel")
      expect(response.body).to include("href=\"/admin/content/#{node.id}\"")
    end

    it "returns 404 for a non-existent ID" do
      get "/admin/content/999999/edit"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /admin/content/:id" do
    let!(:node) do
      Node.create!(title: "Original Title", slug: "original-title", body: "Original body", published: false)
    end

    context "with valid params" do
      it "updates the node and redirects to the show page" do
        patch "/admin/content/#{node.id}", params: { node: { title: "Updated Title" } }

        expect(response).to redirect_to(admin_content_path(node))
        expect(node.reload.title).to eq("Updated Title")
      end

      it "shows a success flash message after redirect" do
        patch "/admin/content/#{node.id}", params: { node: { title: "Updated Title" } }

        follow_redirect!

        expect(response.body).to include("Node was successfully updated.")
      end

      it "has the flash message in an element with role='status'" do
        patch "/admin/content/#{node.id}", params: { node: { title: "Updated Title" } }

        follow_redirect!

        expect(response.body).to include('role="status"')
        expect(response.body).to include("Node was successfully updated.")
      end
    end

    context "with blank title" do
      it "returns 422 and re-renders the form with errors" do
        patch "/admin/content/#{node.id}", params: { node: { title: "" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Edit Node")
        expect(response.body).to include("role=\"alert\"")
      end

      it "preserves the submitted values in the form" do
        patch "/admin/content/#{node.id}", params: { node: { title: "", body: "Updated body" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Updated body")
      end

      it "marks the title field as aria-invalid" do
        patch "/admin/content/#{node.id}", params: { node: { title: "" } }

        expect(response.body).to include('aria-invalid="true"')
        expect(response.body).to include("title-error")
      end
    end

    context "slug handling" do
      it "returns 422 with error when slug duplicates another node" do
        Node.create!(title: "Other Node", slug: "taken-slug")

        patch "/admin/content/#{node.id}", params: { node: { slug: "taken-slug" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("slug-error")
      end
    end

    context "published flag" do
      it "sets published_at when transitioning from false to true" do
        patch "/admin/content/#{node.id}", params: { node: { published: "1" } }

        node.reload
        expect(node.published).to be true
        expect(node.published_at).not_to be_nil
      end

      it "preserves published_at when unchecking published" do
        node.update!(published: true)
        original_published_at = node.reload.published_at

        patch "/admin/content/#{node.id}", params: { node: { published: "0" } }

        node.reload
        expect(node.published).to be false
        expect(node.published_at).to eq(original_published_at)
      end
    end

    context "strong parameters" do
      it "ignores unpermitted parameters" do
        patch "/admin/content/#{node.id}", params: { node: { title: "Safe Update", created_at: "2000-01-01" } }

        node.reload
        expect(node.title).to eq("Safe Update")
        expect(node.created_at).not_to eq(Time.zone.parse("2000-01-01"))
      end
    end

    it "returns 404 for a non-existent ID" do
      patch "/admin/content/999999", params: { node: { title: "Nope" } }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /admin/content/:id" do
    let!(:node) do
      Node.create!(title: "Doomed Node", slug: "doomed-node", body: "Goodbye")
    end

    it "deletes the node and redirects to the listing page" do
      expect {
        delete "/admin/content/#{node.id}"
      }.to change(Node, :count).by(-1)

      expect(response).to redirect_to(admin_content_index_path)
    end

    it "shows a success flash message after redirect" do
      delete "/admin/content/#{node.id}"

      follow_redirect!

      expect(response.body).to include("Node was successfully deleted.")
    end

    it "has the flash message in an element with role='status'" do
      delete "/admin/content/#{node.id}"

      follow_redirect!

      expect(response.body).to include('role="status"')
      expect(response.body).to include("Node was successfully deleted.")
    end

    it "removes the node from the listing" do
      delete "/admin/content/#{node.id}"

      follow_redirect!

      expect(response.body).not_to include("Doomed Node")
    end

    it "returns 404 for a non-existent ID" do
      delete "/admin/content/999999"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a non-integer ID" do
      delete "/admin/content/abc"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "show page delete button" do
    let!(:node) { Node.create!(title: "Test Node") }

    it "has a delete button rendered as a form with DELETE method" do
      get "/admin/content/#{node.id}"

      expect(response.body).to include("Delete Node")
      expect(response.body).to include('name="_method"')
      expect(response.body).to include('value="delete"')
    end

    it "includes a confirmation dialog message" do
      get "/admin/content/#{node.id}"

      expect(response.body).to include("Are you sure you want to delete this node? This action cannot be undone.")
    end
  end
end
