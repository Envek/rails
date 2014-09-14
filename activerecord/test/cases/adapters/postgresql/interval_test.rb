# encoding: utf-8
require 'cases/helper'

class PostgresqlIntervalTest < ActiveRecord::TestCase
  class IntervalDataType < ActiveRecord::Base
    self.table_name = 'interval_data_type'
  end

  def setup
    @connection = ActiveRecord::Base.connection
    begin
      @connection.transaction do
        @connection.create_table('interval_data_type') do |t|
          t.interval 'maximum_term'
          t.interval 'minimum_term', precision: 3
        end
      end
    end
    @column_max = IntervalDataType.columns_hash['maximum_term']
    @column_min = IntervalDataType.columns_hash['minimum_term']
    assert(@column_max.is_a?(ActiveRecord::ConnectionAdapters::PostgreSQLColumn))
    assert(@column_min.is_a?(ActiveRecord::ConnectionAdapters::PostgreSQLColumn))
    assert_equal nil, @column_max.precision
    assert_equal 3,   @column_min.precision
  end

  teardown do
    @connection.execute 'DROP TABLE IF EXISTS interval_data_type'
  end

  def test_column
    assert_equal :interval,     @column_max.type
    assert_equal :interval,     @column_min.type
    assert_equal 'interval',    @column_max.sql_type
    assert_equal 'interval(3)', @column_min.sql_type
  end

  def test_interval_type
    IntervalDataType.create!(
      maximum_term: 6.year + 5.month + 4.days + 3.hours + 2.minutes + 1.seconds,
      minimum_term: 1.year + 2.month + 3.days + 4.hours + 5.minutes + (6.234567).seconds,
    )
    i = IntervalDataType.last!
    assert_equal 'P6Y5M4DT3H2M1S',     i.maximum_term.iso8601
    assert_equal 'P1Y2M3DT4H5M6.235S', i.minimum_term.iso8601
  end

  def test_interval_type_cast_string_and_numeric
    IntervalDataType.create!(maximum_term: '1 year 2 minutes', minimum_term: 36000)
    i = IntervalDataType.last!
    assert_equal 'P1YT2M', i.maximum_term.iso8601
    assert_equal 'PT10H',  i.minimum_term.iso8601
  end


  def test_type_cast_from_database_postgres_format
    [
        ['1 year 2 mons',                     'P1Y2M'],
        ['3 days 04:05:06',                   'P3DT4H5M6S'],
        ['-1 year -2 mons +3 days -04:05:06', 'P-1Y-2M3DT-4H-5M-6S'],
    ].each do |postgres_duration, expected_in_iso8601|
      assert_equal(expected_in_iso8601, @column_max.type_cast_from_database(postgres_duration).iso8601)
    end
  end

  def test_type_cast_from_database_postgres_verbose_format
    [
        ['@ 1 year 2 mons',                                   'P1Y2M'],
        ['@ 3 days 4 hours 5 mins 6 secs',                    'P3DT4H5M6S'],
        ['@ 1 year 2 mons -3 days 4 hours 5 mins 6 secs ago', 'P-1Y-2M3DT-4H-5M-6S'],
    ].each do |postgres_duration, expected_in_iso8601|
      assert_equal(expected_in_iso8601, @column_max.type_cast_from_database(postgres_duration).iso8601)
    end
  end

  def test_type_cast_from_database_sql_standard_format
    [
      ['1-2',              'P1Y2M'],
      ['3 4:05:06',        'P3DT4H5M6S'],
      ['-1-2 +3 -4:05:06', 'P-1Y-2M3DT-4H-5M-6S'],
    ].each do |sql_duration, expected_in_iso8601|
      assert_equal(expected_in_iso8601, @column_max.type_cast_from_database(sql_duration).iso8601)
    end
  end

  def test_type_cast_from_database_iso8601_format
    [
        ['P1Y2M',               'P1Y2M'],
        ['P3DT4H5M6S',          'P3DT4H5M6S'],
        ['P-1Y-2M3DT-4H-5M-6S', 'P-1Y-2M3DT-4H-5M-6S'],
    ].each do |sql_duration, expected_in_iso8601|
      assert_equal(expected_in_iso8601, @column_max.type_cast_from_database(sql_duration).iso8601)
    end
  end

end
