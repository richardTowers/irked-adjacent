class CreateFieldDefinitions < ActiveRecord::Migration[8.1]
  def change
    create_table :field_definitions do |t|
      t.references :content_type, null: false, foreign_key: true
      t.string :name, null: false
      t.string :api_key, null: false
      t.string :field_type, null: false
      t.boolean :required, null: false, default: false
      t.integer :position, null: false, default: 0
      t.json :validations

      t.timestamps
    end

    add_index :field_definitions, [:content_type_id, :api_key], unique: true
  end
end
