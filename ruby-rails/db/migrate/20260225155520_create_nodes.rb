class CreateNodes < ActiveRecord::Migration[8.1]
  def change
    create_table :nodes do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.text :body
      t.boolean :published, null: false, default: false
      t.datetime :published_at

      t.timestamps
    end

    add_index :nodes, :slug, unique: true
  end
end
