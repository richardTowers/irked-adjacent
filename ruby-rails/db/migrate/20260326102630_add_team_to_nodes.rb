class AddTeamToNodes < ActiveRecord::Migration[8.1]
  def change
    add_reference :nodes, :team, null: true, foreign_key: true, index: true
  end
end
