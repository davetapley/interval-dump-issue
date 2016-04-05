class CreateWidgets < ActiveRecord::Migration
  def change
    create_table :widgets do |t|
      t.interval :foo, default: '00:00:00', null: false
    end
  end
end
