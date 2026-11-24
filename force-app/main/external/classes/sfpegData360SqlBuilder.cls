/***
* @description  Utility class translating the table selections of the Apex Connector
*               Framework (i.e. SOQL queries on External Objects) into Data 360 SQL
*               queries on the corresponding DMOs, and mapping back the SQL results
*               into External Object rows.
*               DMO and field names come from validated configuration, whereas all
*               filter values are typed and escaped to prevent any SQL injection.
*               Part of the PEG_DC package external connector.
* @author       P-E GROS
* @date         October 2026
* @see          sfpegData360Connection
* @see          PEG_DC package (https://github.com/pegros/PEG_DC)
*
* Legal Notice
*
* MIT License
*
* Copyright (c) 2026 pegros
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
***/

@SuppressWarnings('PMD.ClassNamingConventions,PMD.FieldNamingConventions')
public with sharing class sfpegData360SqlBuilder {

    //#####################################################
    // Static Configuration
    //#####################################################

    /***
    * @description  Max number of rows fetched when no limit is provided by the platform.
    ***/
    @TestVisible
    private static final Integer DEFAULT_MAX_ROWS = 2000;


    //#####################################################
    // Instance Variables
    //#####################################################

    /***
    * @description  Configuration of the table queried.
    ***/
    private sfpegData360Connection.TableConfig table;

    /***
    * @description  Columns returned by the last select query built (in SQL select order,
    *               unmapped columns such as DisplayUrl being returned as null).
    ***/
    @TestVisible
    private List<sfpegData360Connection.ColumnConfig> selectedColumns;


    //#####################################################
    // Constructor
    //#####################################################

    public sfpegData360SqlBuilder(final sfpegData360Connection.TableConfig table) {
        this.table = table;
    }


    //#####################################################
    // Public Methods
    //#####################################################

    /***
    * @description  Checks if a table selection corresponds to a COUNT() query.
    ***/
    public static Boolean isCount(final DataSource.TableSelection selection) {
        return (selection.columnsSelected != null)
            && (selection.columnsSelected.size() == 1)
            && (selection.columnsSelected[0].aggregation == DataSource.QueryAggregation.COUNT);
    }

    /***
    * @description  Builds a SQL COUNT(*) query for a table selection.
    ***/
    public String buildCount(final DataSource.TableSelection selection) {
        String sqlQuery = 'SELECT COUNT(*) FROM ' + this.table.dmoName + buildWhere(selection.filter);
        System.debug(LoggingLevel.FINE,'buildCount: SQL query built ' + sqlQuery);
        return sqlQuery;
    }

    /***
    * @description  Builds a SQL select query for a table selection, including paging
    *               (ExternalId being always selected).
    ***/
    public String buildSelect(final DataSource.TableSelection selection, final Integer maxResults, final Integer offset) {
        this.selectedColumns = new List<sfpegData360Connection.ColumnConfig>();
        Set<String> selectedNames = new Set<String>();
        if ((selection.columnsSelected == null) || (selection.columnsSelected.isEmpty())) {
            for (sfpegData360Connection.ColumnConfig iter : this.table.columns) {
                registerSelected(iter, selectedNames);
            }
        }
        else {
            registerSelected(this.table.getColumn(sfpegData360Connection.EXTERNAL_ID), selectedNames);
            for (DataSource.ColumnSelection iter : selection.columnsSelected) {
                registerSelected(this.table.getColumn(iter.columnName), selectedNames);
            }
        }

        List<String> sqlFields = new List<String>();
        for (sfpegData360Connection.ColumnConfig iter : this.selectedColumns) {
            if (iter.dmoField != null) sqlFields.add(iter.dmoField);
        }

        String sqlQuery = 'SELECT ' + String.join(sqlFields, ', ')
                        + ' FROM ' + this.table.dmoName
                        + buildWhere(selection.filter)
                        + buildOrder(selection.order, ((offset != null) && (offset > 0)))
                        + ' LIMIT ' + (((maxResults == null) || (maxResults <= 0)) ? DEFAULT_MAX_ROWS : maxResults)
                        + (((offset != null) && (offset > 0)) ? ' OFFSET ' + offset : '');
        System.debug(LoggingLevel.FINE,'buildSelect: SQL query built ' + sqlQuery);
        return sqlQuery;
    }

    /***
    * @description  Maps a SQL result row (values in SQL select order) into an External
    *               Object row (keyed by column name), converting values to column types.
    ***/
    public Map<String,Object> mapRow(final List<Object> values) {
        Map<String,Object> row = new Map<String,Object>();
        Integer valueIndex = 0;
        for (sfpegData360Connection.ColumnConfig iter : this.selectedColumns) {
            if (iter.dmoField == null) {
                row.put(iter.name, null);
            }
            else {
                row.put(iter.name, iter.convert(values.get(valueIndex++)));
            }
        }
        return row;
    }


    //#####################################################
    // Private Utility Methods
    //#####################################################

    private void registerSelected(final sfpegData360Connection.ColumnConfig column, Set<String> selectedNames) {
        if (selectedNames.add(column.name)) this.selectedColumns.add(column);
    }

    /***
    * @description  Builds the WHERE clause of a SQL query (empty if no filter).
    ***/
    @TestVisible
    private String buildWhere(final DataSource.Filter filter) {
        String condition = buildFilter(filter);
        return String.isBlank(condition) ? '' : ' WHERE ' + condition;
    }

    /***
    * @description  Recursively translates a Connector Framework filter into a SQL condition.
    ***/
    @TestVisible
    private String buildFilter(final DataSource.Filter filter) {
        if (filter == null) return null;
        switch on filter.type {
            when AND_, OR_ {
                List<String> conditions = new List<String>();
                for (DataSource.Filter iter : filter.subfilters) {
                    conditions.add('(' + buildFilter(iter) + ')');
                }
                if (conditions.isEmpty()) throw new DataSource.DataSourceException('Empty ' + filter.type + ' filter');
                return String.join(conditions, (filter.type == DataSource.FilterType.AND_) ? ' AND ' : ' OR ');
            }
            when NOT_ {
                if ((filter.subfilters == null) || (filter.subfilters.size() != 1)) {
                    throw new DataSource.DataSourceException('Invalid NOT filter');
                }
                return 'NOT (' + buildFilter(filter.subfilters[0]) + ')';
            }
            when else {
                return buildCondition(filter);
            }
        }
    }

    /***
    * @description  Translates a Connector Framework elementary filter into a SQL condition
    *               (LIKE operators being case insensitive, as in SOQL).
    ***/
    @TestVisible
    private String buildCondition(final DataSource.Filter filter) {
        sfpegData360Connection.ColumnConfig column = this.table.getColumn(filter.columnName);
        if (column.dmoField == null) {
            throw new DataSource.DataSourceException('Filtering not supported on column ' + column.name);
        }
        String field = column.dmoField;
        Object value = filter.columnValue;

        switch on filter.type {
            when EQUALS {
                return (value == null) ? field + ' IS NULL' : field + ' = ' + formatValue(column, value);
            }
            when NOT_EQUALS {
                return (value == null) ? field + ' IS NOT NULL'
                    : '(' + field + ' <> ' + formatValue(column, value) + ' OR ' + field + ' IS NULL)';
            }
            when LESS_THAN {
                return field + ' < ' + formatValue(column, value);
            }
            when LESS_THAN_OR_EQUAL_TO {
                return field + ' <= ' + formatValue(column, value);
            }
            when GREATER_THAN {
                return field + ' > ' + formatValue(column, value);
            }
            when GREATER_THAN_OR_EQUAL_TO {
                return field + ' >= ' + formatValue(column, value);
            }
            when LIKE_ {
                // SOQL and SQL LIKE wildcards (% and _) are the same
                return field + ' ILIKE ' + quote(String.valueOf(value));
            }
            when CONTAINS {
                return field + ' ILIKE ' + quote('%' + escapeLike(String.valueOf(value)) + '%');
            }
            when STARTS_WITH {
                return field + ' ILIKE ' + quote(escapeLike(String.valueOf(value)) + '%');
            }
            when ENDS_WITH {
                return field + ' ILIKE ' + quote('%' + escapeLike(String.valueOf(value)));
            }
            when else {
                throw new DataSource.DataSourceException('Unsupported filter type ' + filter.type);
            }
        }
    }

    /***
    * @description  Builds the ORDER BY clause of a SQL query (null values being sorted as
    *               in SOQL), the ExternalId being used by default when paging is required.
    ***/
    @TestVisible
    private String buildOrder(final List<DataSource.Order> orders, final Boolean isPaging) {
        List<String> clauses = new List<String>();
        if (orders != null) {
            for (DataSource.Order iter : orders) {
                sfpegData360Connection.ColumnConfig column = this.table.getColumn(iter.columnName);
                if (column.dmoField == null) {
                    throw new DataSource.DataSourceException('Sorting not supported on column ' + column.name);
                }
                clauses.add(column.dmoField
                    + ((iter.direction == DataSource.OrderDirection.DESCENDING) ? ' DESC NULLS LAST' : ' ASC NULLS FIRST'));
            }
        }
        if ((clauses.isEmpty()) && (isPaging)) {
            clauses.add(this.table.getColumn(sfpegData360Connection.EXTERNAL_ID).dmoField + ' ASC');
        }
        return clauses.isEmpty() ? '' : ' ORDER BY ' + String.join(clauses, ', ');
    }

    /***
    * @description  Formats a filter value as a SQL literal, according to its Apex type
    *               (or to the column type for String values on non text columns).
    ***/
    @TestVisible
    private static String formatValue(final sfpegData360Connection.ColumnConfig column, final Object value) {
        if (value == null) return 'NULL';
        if (value instanceof Boolean) return ((Boolean) value) ? 'TRUE' : 'FALSE';
        if (value instanceof Decimal) return ((Decimal) value).toPlainString();
        if ((value instanceof Integer) || (value instanceof Long)) return String.valueOf(value);
        if (value instanceof Double) return Decimal.valueOf((Double) value).toPlainString();
        // Date tested first (a Date being also an instance of Datetime in Apex)
        if (value instanceof Date) return 'DATE \'' + String.valueOf((Date) value) + '\'';
        if (value instanceof Datetime) return 'TIMESTAMP \'' + ((Datetime) value).formatGmt('yyyy-MM-dd HH:mm:ss') + '\'';

        String stringValue = String.valueOf(value);
        switch on column.dataType {
            when 'Number' {
                // Parsing prevents any injection via non numeric values
                return Decimal.valueOf(stringValue).toPlainString();
            }
            when 'Boolean' {
                return Boolean.valueOf(stringValue) ? 'TRUE' : 'FALSE';
            }
            when else {
                return quote(stringValue);
            }
        }
    }

    /***
    * @description  Formats a String as a SQL string literal (single quotes being doubled).
    ***/
    @TestVisible
    private static String quote(final String value) {
        return '\'' + (value == null ? '' : value.replace('\'', '\'\'')) + '\'';
    }

    /***
    * @description  Escapes the LIKE wildcards (and escape character) within a String.
    ***/
    @TestVisible
    private static String escapeLike(final String value) {
        return (value == null) ? '' : value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }
}
