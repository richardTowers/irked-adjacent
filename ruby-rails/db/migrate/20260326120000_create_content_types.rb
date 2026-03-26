class CreateContentTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :content_types do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.references :team, null: false, foreign_key: true

      t.timestamps
    end

    add_index :content_types, :slug, unique: true
  end
end
