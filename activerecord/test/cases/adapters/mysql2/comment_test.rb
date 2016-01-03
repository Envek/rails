require 'cases/helper'
require 'support/schema_dumping_helper'

class Mysql2CommentTest < ActiveRecord::Mysql2TestCase
  include SchemaDumpingHelper
  self.use_transactional_tests = false

  class MyComment < ActiveRecord::Base
    self.table_name = 'my_comments'
  end

  def setup
    @connection = ActiveRecord::Base.connection

    @connection.transaction do
      @table = @connection.create_table('my_comments', comment: 'A table with comment', force: true) do |t|
        t.string  'name',    comment: 'Comment should help clarify the column purpose'
        t.boolean 'obvious', comment: 'Question is: should you comment obviously named objects?'
        t.string  'content'
        t.index   'name',    comment: %Q["Very important" index that powers all the performance.\nAnd it's fun!]
      end
    end
  end

  teardown do
    @connection.drop_table 'my_comments', if_exists: true
  end

  def test_column_created_in_block
    MyComment.reset_column_information
    column = MyComment.columns_hash['name']
    assert_equal :string, column.type
    assert_equal 'varchar(255)', column.sql_type
    assert_equal 'Comment should help clarify the column purpose', column.comment
  end

  def test_add_column_with_comment_later
    @connection.add_column :my_comments, :rating, :integer, comment: 'I am running out of imagination'
    MyComment.reset_column_information
    column = MyComment.columns_hash['rating']

    assert_equal :integer, column.type
    assert_equal 'I am running out of imagination', column.comment
  end

  def test_add_index_with_comment_later
    @connection.add_index :my_comments, :obvious, name: 'idx_obvious', comment: 'We need to see obvious comments'
    index = @connection.indexes('my_comments').find { |idef| idef.name == 'idx_obvious' }
    assert_equal 'We need to see obvious comments', index.comment
  end

  def test_add_comment_to_column
    @connection.change_column :my_comments, :content, :string, comment: 'Whoa, content describes itself!'

    MyComment.reset_column_information
    column = MyComment.columns_hash['content']

    assert_equal :string, column.type
    assert_equal 'Whoa, content describes itself!', column.comment
  end

  def test_remove_comment_from_column
    @connection.change_column :my_comments, :obvious, :string, comment: nil

    MyComment.reset_column_information
    column = MyComment.columns_hash['obvious']

    assert_equal :string, column.type
    assert_nil column.comment
  end

  def test_schema_dump_with_comments
    # Do all the stuff from other tests
    @connection.add_column    :my_comments, :rating, :integer, comment: 'I am running out of imagination'
    @connection.change_column :my_comments, :content, :string, comment: 'Whoa, content describes itself!'
    @connection.change_column :my_comments, :obvious, :string, comment: nil
    @connection.add_index     :my_comments, :obvious, name: 'idx_obvious', comment: 'We need to see obvious comments'
    # And check that these changes are reflected in dump
    output = dump_table_schema 'my_comments'
    assert_match %r[create_table "my_comments", .* comment: "A table with comment"], output
    assert_match %r[t\.string\s+"name",\s+comment: "Comment should help clarify the column purpose"], output
    assert_match %r[t\.string\s+"obvious"\n], output
    assert_match %r[t\.string\s+"content",\s+comment: "Whoa, content describes itself!"], output
    assert_match %r[t\.integer\s+"rating",\s+comment: "I am running out of imagination"], output
    assert_match %r[t.index\s+.+\s+comment: "\\"Very important\\" index that powers all the performance.\\nAnd it's fun!"], output
    assert_match %r[t.index\s+.+\s+name: "idx_obvious",.+\s+comment: "We need to see obvious comments"], output
  end
end
