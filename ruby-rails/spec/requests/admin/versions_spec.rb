require "rails_helper"

RSpec.describe "Admin::Versions", type: :request do
  let(:main_branch) { Branch.find_by!(name: "main") }
  let(:published_branch) { Branch.find_by!(name: "published") }

  def create_node(title: "Test Node", slug: nil, body: "Some body")
    Node.create_with_version(title: title, slug: slug, body: body)
  end

  def switch_branch(branch)
    post "/admin/switch-branch", params: { branch_id: branch.id }
  end

  describe "GET /admin/content/:id/history" do
    it "returns 200 and displays the page heading" do
      node, version = create_node(title: "My Page")
      version.commit!("Initial commit")

      get "/admin/content/#{node.id}/history"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("History for My Page")
    end

    it "lists committed versions in reverse chronological order" do
      node, v1 = create_node(title: "Page", body: "v1")
      v1.commit!("First commit")

      v2 = Version.create!(node: node, branch: main_branch, title: "Page", body: "v2", parent_version: v1)
      v2.commit!("Second commit")

      get "/admin/content/#{node.id}/history"

      body = response.body
      second_pos = body.index("Second commit")
      first_pos = body.index("First commit")
      expect(second_pos).to be < first_pos
    end

    it "shows the uncommitted draft at the top" do
      node, v1 = create_node(title: "Page")
      v1.commit!("Initial")

      Version.create!(node: node, branch: main_branch, title: "Draft title", body: "draft", parent_version: v1)

      get "/admin/content/#{node.id}/history"

      body = response.body
      draft_pos = body.index("Uncommitted draft")
      initial_pos = body.index("Initial")
      expect(draft_pos).to be < initial_pos
    end

    it "shows commit message, timestamp, and view link for each version" do
      node, v1 = create_node(title: "Page")
      v1.commit!("My commit message")

      get "/admin/content/#{node.id}/history"

      expect(response.body).to include("My commit message")
      expect(response.body).to include(v1.committed_at.strftime("%-d %B %Y %H:%M"))
      expect(response.body).to include("View")
    end

    it "shows source branch name for merge commits" do
      node, v1 = create_node(title: "Page")
      v1.commit!("Initial")

      Version.publish!(v1)

      switch_branch(published_branch)
      get "/admin/content/#{node.id}/history"

      expect(response.body).to include("Merged from main")
    end

    it "shows 'Not yet committed' for uncommitted draft timestamp" do
      node, _v1 = create_node(title: "Page")

      get "/admin/content/#{node.id}/history"

      expect(response.body).to include("Not yet committed")
    end

    it "shows 'No version history' when no versions exist on branch" do
      node, _v1 = create_node(title: "Page")
      feature = Branch.create!(name: "empty-branch")
      switch_branch(feature)

      get "/admin/content/#{node.id}/history"

      expect(response.body).to include("No version history.")
    end

    it "has a Back to Node link" do
      node, _v1 = create_node(title: "Page")

      get "/admin/content/#{node.id}/history"

      expect(response.body).to include("Back to Node")
      expect(response.body).to include("/admin/content/#{node.id}")
    end

    it "returns 404 for non-existent node" do
      get "/admin/content/999999/history"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for non-integer node id" do
      get "/admin/content/abc/history"

      expect(response).to have_http_status(:not_found)
    end

    it "uses proper table headers" do
      node, _v1 = create_node(title: "Page")

      get "/admin/content/#{node.id}/history"

      expect(response.body).to include("<th scope=\"col\">Commit Message</th>")
      expect(response.body).to include("<th scope=\"col\">Committed At</th>")
      expect(response.body).to include("<th scope=\"col\">Source</th>")
    end
  end

  describe "GET /admin/content/:id/versions/:version_id" do
    it "returns 200 and displays the version content" do
      node, v1 = create_node(title: "My Title", body: "My body text")
      v1.commit!("Initial commit")

      get "/admin/content/#{node.id}/versions/#{v1.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Initial commit")
      expect(response.body).to include("My Title")
      expect(response.body).to include("My body text")
    end

    it "shows commit message as heading for committed versions" do
      node, v1 = create_node(title: "Page")
      v1.commit!("Big refactor")

      get "/admin/content/#{node.id}/versions/#{v1.id}"

      expect(response.body).to include("<h1>Big refactor</h1>")
    end

    it "shows 'Uncommitted draft' as heading for uncommitted versions" do
      node, v1 = create_node(title: "Page")

      get "/admin/content/#{node.id}/versions/#{v1.id}"

      expect(response.body).to include("<h1>Uncommitted draft</h1>")
    end

    it "shows 'Not yet committed' for uncommitted version timestamp" do
      node, v1 = create_node(title: "Page")

      get "/admin/content/#{node.id}/versions/#{v1.id}"

      expect(response.body).to include("Not yet committed")
    end

    it "shows 'None' for commit message of uncommitted version" do
      node, v1 = create_node(title: "Page")

      get "/admin/content/#{node.id}/versions/#{v1.id}"

      body = response.body
      cm_dt = body.index("<dt>Commit Message</dt>")
      cm_section = body[cm_dt..cm_dt + 100]
      expect(cm_section).to include("<dd>None</dd>")
    end

    it "shows parent version link when parent exists" do
      node, v1 = create_node(title: "Page")
      v1.commit!("First")

      v2 = Version.create!(node: node, branch: main_branch, title: "Page v2", body: "v2", parent_version: v1)

      get "/admin/content/#{node.id}/versions/#{v2.id}"

      expect(response.body).to include("View parent version")
      expect(response.body).to include("/admin/content/#{node.id}/versions/#{v1.id}")
    end

    it "shows 'None (initial version)' when no parent" do
      node, v1 = create_node(title: "Page")

      get "/admin/content/#{node.id}/versions/#{v1.id}"

      expect(response.body).to include("None (initial version)")
    end

    it "shows source version link when source exists" do
      node, v1 = create_node(title: "Page")
      v1.commit!("Initial")

      published_version = Version.publish!(v1)

      get "/admin/content/#{node.id}/versions/#{published_version.id}"

      expect(response.body).to include("View source version (main)")
      expect(response.body).to include("/admin/content/#{node.id}/versions/#{v1.id}")
    end

    it "shows 'None' when no source version" do
      node, v1 = create_node(title: "Page")

      get "/admin/content/#{node.id}/versions/#{v1.id}"

      body = response.body
      sv_dt = body.index("<dt>Source Version</dt>")
      sv_section = body[sv_dt..sv_dt + 100]
      expect(sv_section).to match(/<dd>\s*None\s*<\/dd>/)
    end

    it "shows 'Revert to This Version' for committed versions" do
      node, v1 = create_node(title: "Page")
      v1.commit!("Initial")

      get "/admin/content/#{node.id}/versions/#{v1.id}"

      expect(response.body).to include("Revert to This Version")
    end

    it "does not show 'Revert to This Version' for uncommitted versions" do
      node, v1 = create_node(title: "Page")

      get "/admin/content/#{node.id}/versions/#{v1.id}"

      expect(response.body).not_to include("Revert to This Version")
    end

    it "does not show 'Revert to This Version' on published branch" do
      node, v1 = create_node(title: "Page")
      v1.commit!("Initial")

      switch_branch(published_branch)

      get "/admin/content/#{node.id}/versions/#{v1.id}"

      expect(response.body).not_to include("Revert to This Version")
    end

    it "works for versions on a different branch than selected" do
      node, v1 = create_node(title: "Page")
      v1.commit!("On main")

      feature = Branch.create!(name: "feature-x")
      switch_branch(feature)

      get "/admin/content/#{node.id}/versions/#{v1.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("On main")
    end

    it "has Back to History and Back to Node links" do
      node, v1 = create_node(title: "Page")

      get "/admin/content/#{node.id}/versions/#{v1.id}"

      expect(response.body).to include("Back to History")
      expect(response.body).to include("Back to Node")
    end

    it "returns 404 for non-existent version" do
      node, _v1 = create_node(title: "Page")

      get "/admin/content/#{node.id}/versions/999999"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when version belongs to a different node" do
      node1, _v1 = create_node(title: "Node 1", slug: "node-1")
      node2, v2 = create_node(title: "Node 2", slug: "node-2")

      get "/admin/content/#{node1.id}/versions/#{v2.id}"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for non-integer version id" do
      node, _v1 = create_node(title: "Page")

      get "/admin/content/#{node.id}/versions/abc"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for non-existent node" do
      get "/admin/content/999999/versions/1"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /admin/content/:id/versions/:version_id/revert" do
    it "creates an uncommitted draft with the target version's content" do
      node, v1 = create_node(title: "Original", body: "Original body")
      v1.commit!("Initial")

      v2 = Version.create!(node: node, branch: main_branch, title: "Updated", body: "New body", parent_version: v1)
      v2.commit!("Second")

      post "/admin/content/#{node.id}/versions/#{v1.id}/revert"

      expect(response).to redirect_to(admin_content_path(node))

      draft = node.versions.uncommitted.find_by(branch: main_branch)
      expect(draft).to be_present
      expect(draft.title).to eq("Original")
      expect(draft.body).to eq("Original body")
      expect(draft.source_version_id).to eq(v1.id)
      expect(draft.parent_version_id).to eq(v2.id)
    end

    it "updates existing uncommitted draft when one exists" do
      node, v1 = create_node(title: "Original", body: "Original body")
      v1.commit!("Initial")

      v2 = Version.create!(node: node, branch: main_branch, title: "Draft", body: "Draft body", parent_version: v1)

      expect {
        post "/admin/content/#{node.id}/versions/#{v1.id}/revert"
      }.not_to change(Version, :count)

      v2.reload
      expect(v2.title).to eq("Original")
      expect(v2.body).to eq("Original body")
    end

    it "redirects with flash notice including timestamp" do
      node, v1 = create_node(title: "Page")
      v1.commit!("Initial")

      post "/admin/content/#{node.id}/versions/#{v1.id}/revert"

      expect(response).to redirect_to(admin_content_path(node))
      follow_redirect!
      expect(response.body).to include("Reverted to version from")
      expect(response.body).to include(v1.committed_at.strftime("%-d %B %Y %H:%M"))
    end

    it "does not commit the reverted content" do
      node, v1 = create_node(title: "Page")
      v1.commit!("Initial")

      v2 = Version.create!(node: node, branch: main_branch, title: "V2", body: "v2", parent_version: v1)
      v2.commit!("Second")

      post "/admin/content/#{node.id}/versions/#{v1.id}/revert"

      draft = node.versions.uncommitted.find_by(branch: main_branch)
      expect(draft).to be_present
      expect(draft.committed_at).to be_nil
    end

    it "redirects with alert when on published branch" do
      node, v1 = create_node(title: "Page")
      v1.commit!("Initial")

      switch_branch(published_branch)

      post "/admin/content/#{node.id}/versions/#{v1.id}/revert"

      expect(response).to redirect_to(admin_content_path(node))
      follow_redirect!
      expect(response.body).to include("Cannot revert on the published branch.")
    end

    it "redirects with alert when reverting to the current draft" do
      node, v1 = create_node(title: "Page")

      post "/admin/content/#{node.id}/versions/#{v1.id}/revert"

      expect(response).to redirect_to(admin_content_path(node))
      follow_redirect!
      expect(response.body).to include("Cannot revert to the current draft.")
    end

    it "returns 404 for non-existent node" do
      post "/admin/content/999999/versions/1/revert"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when version belongs to a different node" do
      node1, _v1 = create_node(title: "Node 1", slug: "node-1")
      _node2, v2 = create_node(title: "Node 2", slug: "node-2")

      post "/admin/content/#{node1.id}/versions/#{v2.id}/revert"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for non-existent version" do
      node, _v1 = create_node(title: "Page")

      post "/admin/content/#{node.id}/versions/999999/revert"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "show page History link" do
    it "includes a History link on the node show page" do
      node, _v1 = create_node(title: "Page")

      get "/admin/content/#{node.id}"

      expect(response.body).to include("History")
      expect(response.body).to include("/admin/content/#{node.id}/history")
    end
  end
end
