require "rails_helper"

RSpec.describe "Admin::Content", type: :request do
  let(:main_branch) { Branch.find_by!(name: "main") }

  def create_node(title: "Test Node", slug: nil, body: nil)
    Node.create_with_version(title: title, slug: slug, body: body)
  end

  describe "GET /admin/content" do
    context "when there are no nodes" do
      it "returns 200 and shows the empty state" do
        get "/admin/content"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No nodes yet.")
      end
    end

    context "when nodes exist" do
      let!(:older_node) do
        node, version = create_node(title: "Older Post", body: "Older body")
        version.commit!("Initial commit")
        node
      end

      let!(:newer_node) do
        create_node(title: "Newer Post", body: "Newer body").first
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

        # older_node was committed, newer_node is still a draft
        body = response.body

        # Find the row for each node and check status
        older_row = body[body.index("Older Post")..body.index("Older Post") + 200]
        newer_row = body[body.index("Newer Post")..body.index("Newer Post") + 200]

        expect(older_row).to include("Committed")
        expect(newer_row).to include("Draft")
      end
    end

    it "includes a 'New Node' link pointing to /admin/content/new" do
      get "/admin/content"

      expect(response.body).to include("New Node")
      expect(response.body).to include("href=\"/admin/content/new\"")
    end
  end

  describe "GET /admin/content/:id" do
    context "when the current version is uncommitted (draft)" do
      let!(:node) do
        node, _version = create_node(
          title: "Test Node",
          body: "Some <strong>bold</strong> content"
        )
        node
      end

      it "returns 200 and shows the node title" do
        get "/admin/content/#{node.id}"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("<h1>Test Node</h1>")
      end

      it "displays the node details" do
        get "/admin/content/#{node.id}"

        expect(response.body).to include("test-node")
        expect(response.body).to include("Draft")
      end

      it "escapes HTML in the body" do
        get "/admin/content/#{node.id}"

        expect(response.body).to include("&lt;strong&gt;bold&lt;/strong&gt;")
        expect(response.body).not_to include("<strong>bold</strong>")
      end

      it "displays a commit form" do
        get "/admin/content/#{node.id}"

        expect(response.body).to include("Commit message")
        expect(response.body).to include('value="Commit"')
        expect(response.body).to include("commit[commit_message]")
      end

      it "includes action links" do
        get "/admin/content/#{node.id}"

        expect(response.body).to include("Edit Node")
        expect(response.body).to include("href=\"/admin/content/#{node.id}/edit\"")
        expect(response.body).to include("Back to Nodes")
        expect(response.body).to include("href=\"/admin/content\"")
      end
    end

    context "when the current version is committed" do
      let!(:node) do
        node, version = create_node(title: "Committed Node")
        version.commit!("Initial commit")
        node
      end

      it "displays Committed status with commit message" do
        get "/admin/content/#{node.id}"

        expect(response.body).to include("Committed")
        expect(response.body).to include("Initial commit")
      end

      it "does not display the commit form" do
        get "/admin/content/#{node.id}"

        expect(response.body).not_to include('value="Commit"')
        expect(response.body).not_to include("commit[commit_message]")
      end
    end

    it "returns 404 for a non-existent ID" do
      get "/admin/content/999999"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a non-integer ID" do
      get "/admin/content/abc"

      expect(response).to have_http_status(:not_found)
    end

    it "includes an 'Edit Node' link to the edit page" do
      node, _version = create_node(title: "Test Node")

      get "/admin/content/#{node.id}"

      expect(response.body).to include("Edit Node")
      expect(response.body).to include("href=\"/admin/content/#{node.id}/edit\"")
    end
  end

  describe "GET /admin/content/new" do
    it "returns 200 and renders the form" do
      get "/admin/content/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h1>New Node</h1>")
    end

    it "has form fields for title, slug, and body but no published checkbox" do
      get "/admin/content/new"

      expect(response.body).to include("node[title]")
      expect(response.body).to include("node[slug]")
      expect(response.body).to include("node[body]")
      expect(response.body).not_to include("node[published]")
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

      expect(response.body).to include('required="required"')
    end
  end

  describe "POST /admin/content" do
    context "with valid params" do
      it "creates a node and redirects to the show page" do
        expect {
          post "/admin/content", params: { node: { title: "My First Post", body: "Hello world" } }
        }.to change(Node, :count).by(1).and change(Version, :count).by(1)

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

      it "creates an uncommitted version on main" do
        post "/admin/content", params: { node: { title: "Draft Post", body: "Draft body" } }

        version = Version.last
        expect(version.title).to eq("Draft Post")
        expect(version.body).to eq("Draft body")
        expect(version.branch.name).to eq("main")
        expect(version.committed_at).to be_nil
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
        create_node(slug: "taken-slug", title: "Existing")

        post "/admin/content", params: { node: { title: "New Post", slug: "taken-slug" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("slug-error")
      end
    end

    context "strong parameters" do
      it "ignores unpermitted parameters" do
        post "/admin/content", params: { node: { title: "Safe Post", created_at: "2000-01-01" } }

        node = Node.last
        expect(node.created_at).not_to eq(Time.zone.parse("2000-01-01"))
      end
    end
  end

  describe "GET /admin/content/:id/edit" do
    let!(:node) do
      node, _version = create_node(title: "Editable Node", slug: "editable-node", body: "Original body")
      node
    end

    it "returns 200 and displays the edit form" do
      get "/admin/content/#{node.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h1>Edit Node</h1>")
    end

    it "pre-fills the form with the current version's values" do
      get "/admin/content/#{node.id}/edit"

      expect(response.body).to include("Editable Node")
      expect(response.body).to include("Original body")
    end

    it "displays the slug as read-only text" do
      get "/admin/content/#{node.id}/edit"

      expect(response.body).to include("editable-node")
      # Slug should not be an editable input in the edit form
      expect(response.body).not_to include("node[slug]")
    end

    it "has form fields for title and body" do
      get "/admin/content/#{node.id}/edit"

      expect(response.body).to include("node[title]")
      expect(response.body).to include("node[body]")
    end

    it "has a submit button labeled 'Save Draft'" do
      get "/admin/content/#{node.id}/edit"

      expect(response.body).to include("Save Draft")
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

    it "does not create an uncommitted version (side-effect-free)" do
      version_count_before = Version.count
      get "/admin/content/#{node.id}/edit"
      expect(Version.count).to eq(version_count_before)
    end
  end

  describe "PATCH /admin/content/:id" do
    let!(:node) do
      node, _version = create_node(title: "Original Title", slug: "original-title", body: "Original body")
      node
    end

    context "with valid params" do
      it "saves a draft and redirects to the show page" do
        patch "/admin/content/#{node.id}", params: { node: { title: "Updated Title" } }

        expect(response).to redirect_to(admin_content_path(node))
      end

      it "shows a success flash message after redirect" do
        patch "/admin/content/#{node.id}", params: { node: { title: "Updated Title" } }

        follow_redirect!

        expect(response.body).to include("Draft was successfully saved.")
      end

      it "has the flash message in an element with role='status'" do
        patch "/admin/content/#{node.id}", params: { node: { title: "Updated Title" } }

        follow_redirect!

        expect(response.body).to include('role="status"')
        expect(response.body).to include("Draft was successfully saved.")
      end

      it "updates an existing uncommitted version in place" do
        # Node already has an uncommitted version from creation
        version = Version.current_for(node, main_branch)
        expect(version.committed_at).to be_nil

        patch "/admin/content/#{node.id}", params: { node: { title: "Updated Title", body: "Updated body" } }

        version.reload
        expect(version.title).to eq("Updated Title")
        expect(version.body).to eq("Updated body")
      end

      it "creates a new uncommitted version when only committed versions exist" do
        # Commit the existing version first
        version = Version.current_for(node, main_branch)
        version.commit!("First commit")

        expect {
          patch "/admin/content/#{node.id}", params: { node: { title: "New Draft", body: "New body" } }
        }.to change(Version, :count).by(1)

        new_version = Version.current_for(node, main_branch)
        expect(new_version.committed_at).to be_nil
        expect(new_version.title).to eq("New Draft")
        expect(new_version.parent_version).to eq(version)
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

    context "strong parameters" do
      it "ignores unpermitted parameters" do
        patch "/admin/content/#{node.id}", params: { node: { title: "Safe Update", slug: "hacked-slug" } }

        node.reload
        expect(node.slug).to eq("original-title")
      end
    end

    it "returns 404 for a non-existent ID" do
      patch "/admin/content/999999", params: { node: { title: "Nope" } }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /admin/content/:id/commit" do
    let!(:node) do
      node, _version = create_node(title: "Committable Node")
      node
    end

    context "with a valid commit message" do
      it "commits the version and redirects to the show page" do
        post "/admin/content/#{node.id}/commit", params: { commit: { commit_message: "First commit" } }

        expect(response).to redirect_to(admin_content_path(node))
      end

      it "shows a success flash message" do
        post "/admin/content/#{node.id}/commit", params: { commit: { commit_message: "First commit" } }

        follow_redirect!

        expect(response.body).to include("Version was successfully committed.")
        expect(response.body).to include('role="status"')
      end

      it "makes the version immutable" do
        post "/admin/content/#{node.id}/commit", params: { commit: { commit_message: "First commit" } }

        version = Version.committed.where(node: node, branch: main_branch).last
        expect(version.committed_at).to be_present
        expect(version.commit_message).to eq("First commit")
      end
    end

    context "with a blank commit message" do
      it "redirects with an alert" do
        post "/admin/content/#{node.id}/commit", params: { commit: { commit_message: "" } }

        expect(response).to redirect_to(admin_content_path(node))

        follow_redirect!

        expect(response.body).to include("Commit message can&#39;t be blank.")
        expect(response.body).to include('role="alert"')
      end
    end

    context "when no uncommitted version exists" do
      it "redirects with an alert" do
        version = Version.current_for(node, main_branch)
        version.commit!("Already committed")

        post "/admin/content/#{node.id}/commit", params: { commit: { commit_message: "Nothing to commit" } }

        expect(response).to redirect_to(admin_content_path(node))

        follow_redirect!

        expect(response.body).to include("No uncommitted changes to commit.")
        expect(response.body).to include('role="alert"')
      end
    end

    it "returns 404 for a non-existent ID" do
      post "/admin/content/999999/commit", params: { commit: { commit_message: "test" } }

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a non-integer ID" do
      post "/admin/content/abc/commit", params: { commit: { commit_message: "test" } }

      expect(response).to have_http_status(:not_found)
    end

    context "strong parameters" do
      it "only accepts commit_message" do
        post "/admin/content/#{node.id}/commit", params: { commit: { commit_message: "Valid", committed_at: "2000-01-01" } }

        version = Version.committed.where(node: node, branch: main_branch).last
        expect(version.committed_at).not_to eq(Time.zone.parse("2000-01-01"))
      end
    end
  end

  describe "DELETE /admin/content/:id" do
    let!(:node) do
      create_node(title: "Doomed Node", slug: "doomed-node", body: "Goodbye").first
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

    it "cascades to delete all versions" do
      expect {
        delete "/admin/content/#{node.id}"
      }.to change(Version, :count).by(-1)
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
    let!(:node) { create_node(title: "Test Node").first }

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
