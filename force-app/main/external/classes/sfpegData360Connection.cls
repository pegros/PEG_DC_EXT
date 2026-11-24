/***
* @description  Apex Connector Framework connection class exposing Data 360 DMOs
*               (of all active data spaces) as (read-only) Salesforce Connect External
*               Objects. Exposed DMOs and columns are dynamically fetched from the Data
*               360 metadata (via ConnectApi.CdpQuery.getAllMetadata()), their
*               configuration being derived from these metadata.
*               SOQL queries are translated into SQL queries (via sfpegData360SqlBuilder)
*               and executed synchronously via the sfsqlquery framework.
*               Part of the PEG_DC package external connector.
* @author       P-E GROS
* @date         October 2026
* @see          sfpegData360Provider
* @see          sfpegData360SqlBuilder
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
global with sharing class sfpegData360Connection extends DataSource.Connection {

    //#####################################################
    // Static Configuration
    //#####################################################

    /***
    * @description  Default data space, always fetched first (its DMOs taking precedence over
    *               the ones of other data spaces in case of table name conflict).
    ***/
    @TestVisible
    private static final String DEFAULT_DATASPACE = 'default';

    /***
    * @description  Data spaces on which DMOs are fetched (lazily loaded), i.e. the default
    *               data space followed by the other active data spaces of the Org
    *               (see getDataSpaces()).
    ***/
    @TestVisible
    private static List<String> DATASPACES;

    /***
    * @description  Data 360 entity type fetched via ConnectApi.CdpQuery.getAllMetadata().
    ***/
    @TestVisible
    private static final String DMO_ENTITY_TYPE = 'DataModelObject';

    /***
    * @description  Workload name attached to SQL queries (for Salesforce support debugging).
    ***/
    @TestVisible
    private static final String WORKLOAD = 'sfpegData360Connector';

    /***
    * @description  Standard columns of all External Objects.
    ***/
    public static final String EXTERNAL_ID = 'ExternalId';
    public static final String DISPLAY_URL = 'DisplayUrl';

    /***
    * @description  Standard column automatically added by Salesforce to all External Objects
    *               in multi-currency Orgs (and requested in queries), not declared at sync
    *               but mapped to the currency field of the DMO (if any), i.e. the Data 360
    *               record currency system field or a (possibly namespaced) CurrencyIsoCode__c
    *               field, this field being not exposed as a separate column.
    ***/
    public static final String CURRENCY_ISO_CODE = 'CurrencyIsoCode';
    public static final String CURRENCY_FIELD = 'cdp_sys_record_currency__c';
    private static final Pattern CURRENCY_FIELD_PATTERN = Pattern.compile('(?i)^(cdp_sys_record_currency__c|([a-z0-9_]+__)?CurrencyIsoCode__c)$');

    /***
    * @description  Column names which cannot be used (case insensitive).
    ***/
    private static final Set<String> RESERVED_COLUMNS = new Set<String>{'externalid', 'displayurl', 'id', 'currencyisocode'};

    /***
    * @description  Suffixes removed from DMO and DMO field names to derive default table
    *               and column names.
    ***/
    private static final String DMO_SUFFIX = '__dlm';
    private static final String FIELD_SUFFIX = '__c';

    /***
    * @description  Max length of table / column names and of their labels.
    ***/
    private static final Integer MAX_NAME_LENGTH = 40;
    private static final Integer MAX_LABEL_LENGTH = 40;

    /***
    * @description  Max number of targeted DMO metadata fetches when resolving a table name
    *               at query time (before falling back to a full metadata fetch).
    ***/
    private static final Integer MAX_LOOKUPS = 3;

    /***
    * @description  Decimal places of Number columns exposed by default (Data 360 not
    *               providing the scale of numeric fields).
    ***/
    private static final Integer DEFAULT_DECIMALS = 4;

    /***
    * @description  Pattern of valid table / column names (Salesforce API names without suffix).
    ***/
    private static final Pattern API_NAME_PATTERN = Pattern.compile('^[A-Za-z](?!.*__)[A-Za-z0-9_]*(?<!_)$');

    /***
    * @description  Pattern of valid DMO / field names (inserted as is in SQL queries).
    ***/
    private static final Pattern SQL_NAME_PATTERN = Pattern.compile('^[A-Za-z_][A-Za-z0-9_]*$');

    /***
    * @description  Pattern of DMO fields used by default as name column (e.g. ssot__Name__c).
    ***/
    private static final Pattern NAME_FIELD_PATTERN = Pattern.compile('(?i)^([a-z0-9_]+__)?name__c$');

    /***
    * @description  Prefix of DMO fields never exposed as columns (Data 360 key qualifier
    *               technical fields, e.g. KQ_Id__c).
    ***/
    @TestVisible
    private static final String IGNORED_FIELD_PREFIX = 'KQ_';

    /***
    * @description  All exposed tables (lazily loaded from the Data 360 metadata upon full
    *               discovery), keyed by lower case table name.
    ***/
    @TestVisible
    private static Map<String,TableConfig> TABLES;

    /***
    * @description  Tables individually resolved at query time (when no full discovery done),
    *               keyed by lower case table name.
    ***/
    private static Map<String,TableConfig> RESOLVED_TABLES = new Map<String,TableConfig>();

    /***
    * @description  Mock Data 360 metadata items used in tests (ConnectApi.CdpQuery not being
    *               testable), keyed by "data space/DMO name" ("data space/*" for full fetch).
    ***/
    @TestVisible
    private static Map<String,List<Object>> MOCK_METADATA;


    //#####################################################
    // Instance Variables
    //#####################################################

    /***
    * @description  Connection parameters of the External Data Source (not used for now).
    ***/
    private DataSource.ConnectionParams connectionParams;


    //#####################################################
    // Constructor
    //#####################################################

    global sfpegData360Connection(DataSource.ConnectionParams connectionParams) {
        this.connectionParams = connectionParams;
    }


    //#####################################################
    // Connector Framework Implementation
    //#####################################################

    /***
    * @description  Returns the list of tables proposed in the Validate and Sync step of the
    *               External Data Source, i.e. the DMOs available in Data 360.
    ***/
    override global List<DataSource.Table> sync() {
        System.debug('sync: START');
        List<DataSource.Table> tables = new List<DataSource.Table>();
        for (TableConfig iter : getTables().values()) {
            System.debug(LoggingLevel.FINE,'sync: registering table ' + iter.name);
            tables.add(iter.toTable());
        }
        System.debug('sync: END with #tables ' + tables.size());
        return tables;
    }

    /***
    * @description  Executes a SOQL query on an External Object, by translating it into
    *               a SQL query on the corresponding DMO (or a COUNT() query).
    ***/
    override global DataSource.TableResult query(DataSource.QueryContext context) {
        System.debug('query: START');
        DataSource.TableSelection selection = context.tableSelection;
        TableConfig table = getTable(selection.tableSelected);
        System.debug(LoggingLevel.FINE,'query: table fetched ' + table.name);

        sfpegData360SqlBuilder builder = new sfpegData360SqlBuilder(table);
        List<Map<String,Object>> rows = new List<Map<String,Object>>();

        if (sfpegData360SqlBuilder.isCount(selection)) {
            String sqlQuery = builder.buildCount(selection);
            List<List<Object>> results = executeSQL(sqlQuery, table.dataSpace);
            Object countValue = ((results.isEmpty()) || (results[0].isEmpty())) ? 0 : results[0][0];
            rows.add(new Map<String,Object>{
                selection.columnsSelected[0].columnName => Decimal.valueOf(String.valueOf(countValue)).intValue()
            });
            System.debug('query: END with count ' + countValue);
            return DataSource.TableResult.get(context, rows);
        }

        String sqlQuery = builder.buildSelect(selection, context.maxResults, context.offset);
        List<List<Object>> results = executeSQL(sqlQuery, table.dataSpace);
        for (List<Object> iter : results) {
            rows.add(builder.mapRow(iter));
        }
        System.debug('query: END with #rows ' + rows.size());
        return DataSource.TableResult.get(context, rows);
    }

    /***
    * @description  Executes a SOSL search on the External Objects, relying on the standard
    *               utility (query with a filter on the name column of each table).
    ***/
    override global List<DataSource.TableResult> search(DataSource.SearchContext context) {
        System.debug('search: START for ' + context.searchPhrase);
        return DataSource.SearchUtils.searchByName(context, this);
    }


    //#####################################################
    // Configuration Management
    //#####################################################

    /***
    * @description  Returns the configuration of all exposed tables, i.e. all DMOs of all
    *               data spaces (loaded upon first call). Metadata fetch errors on the
    *               default data space are raised, whereas data spaces other than the default
    *               one are ignored on error (e.g. if not accessible to the running user).
    ***/
    @TestVisible
    private static Map<String,TableConfig> getTables() {
        if (TABLES != null) return TABLES;
        System.debug('getTables: START loading configuration');

        Map<String,TableConfig> tableMap = new Map<String,TableConfig>();
        for (String iterSpace : getDataSpaces()) {
            List<Map<String,Object>> iterItems;
            try {
                iterItems = fetchMetadata(iterSpace, null);
            }
            catch (DataSource.DataSourceException e) {
                if (iterSpace == DEFAULT_DATASPACE) throw e;
                System.debug(LoggingLevel.WARN,'getTables: ignoring data space ' + iterSpace + ': ' + e.getMessage());
                continue;
            }
            for (Map<String,Object> iter : iterItems) {
                registerTable(tableMap, buildTable(iter, iterSpace));
            }
        }

        TABLES = tableMap;
        System.debug('getTables: END with #tables ' + TABLES.size());
        return TABLES;
    }

    /***
    * @description  Returns the configuration of a table (exception raised if unknown).
    *               When no full discovery has been done in the transaction, the DMO is
    *               resolved via targeted metadata fetches (on the DMO names possibly
    *               matching the table name), a full discovery being done as last resort.
    ***/
    @TestVisible
    private static TableConfig getTable(final String tableName) {
        System.debug('getTable: START for ' + tableName);
        if (String.isBlank(tableName)) throw new DataSource.DataSourceException('Missing table name');
        String tableKey = tableName.toLowerCase();
        TableConfig table;
        if (TABLES != null) {
            System.debug('getTable: searching in current TABLES ' + TABLES);
            table = TABLES.get(tableKey);
        }
        else {
            System.debug('getTable: registering new TABLES');
            if (!RESOLVED_TABLES.containsKey(tableKey)) RESOLVED_TABLES.put(tableKey, resolveTable(tableName));
            table = RESOLVED_TABLES.get(tableKey);
        }
        if (table == null) throw new DataSource.DataSourceException('Unknown or inactive table ' + tableName);
        System.debug('getTable: END with table ' + table);
        return table;
    }

    /***
    * @description  Resolves the configuration of a single table from the Data 360 metadata
    *               (null if not found).
    ***/
    private static TableConfig resolveTable(final String tableName) {
        System.debug('resolveTable: START for ' + tableName);

        // Default data space checked first (without loading the list of data spaces)
        TableConfig defaultTable = findCandidate(tableName, DEFAULT_DATASPACE);
        if (defaultTable != null) return defaultTable;
        for (String iterSpace : getDataSpaces()) {
            if (iterSpace == DEFAULT_DATASPACE) continue;
            TableConfig table = findCandidate(tableName, iterSpace);
            if (table != null) return table;
        }

        System.debug('resolveTable: END with full discovery fallback');
        return getTables().get(tableName.toLowerCase());
    }

    /***
    * @description  Looks for a table in a data space via targeted metadata fetches on the
    *               DMO names possibly matching the table name (null if not found).
    ***/
    private static TableConfig findCandidate(final String tableName, final String dataSpace) {
        System.debug('findCandidate: START for tableName ' + tableName);
        Integer lookups = 0;
        for (String iter : getDmoCandidates(tableName)) {
            System.debug('findCandidate: testing ' + iter);
            if (lookups++ >= MAX_LOOKUPS) break;
            try {
                TableConfig table = findTable(tableName, dataSpace, iter);
                if (table != null) return table;
            }
            catch (DataSource.DataSourceException e) {
                System.debug(LoggingLevel.FINE,'findCandidate: lookup failed for DMO ' + iter + ' in data space ' + dataSpace + ': ' + e.getMessage());
            }
        }
        System.debug('findCandidate: END with null');
        return null;
    }

    /***
    * @description  Fetches the metadata of a DMO and returns its table configuration if
    *               it matches the requested table name (null otherwise).
    ***/
    private static TableConfig findTable(final String tableName, final String dataSpace, final String dmoName) {
        for (Map<String,Object> iter : fetchMetadata(dataSpace, dmoName)) {
            TableConfig table = buildTable(iter, dataSpace);
            if ((table != null) && (table.name.equalsIgnoreCase(tableName))) {
                System.debug('findTable: table found for DMO ' + table.dmoName);
                return table;
            }
        }
        return null;
    }

    /***
    * @description  Builds the configuration of a table from a DMO metadata item. Returns
    *               null for DMOs not exposable (e.g. without single primary key).
    ***/
    private static TableConfig buildTable(final Map<String,Object> item, final String dataSpace) {
        try {
            return new TableConfig(item, dataSpace);
        }
        catch (DataSource.DataSourceException e) {
            System.debug(LoggingLevel.WARN,'buildTable: ignoring DMO ' + getString(item, 'name') + ': ' + e.getMessage());
            return null;
        }
    }

    /***
    * @description  Registers a table in the exposed tables, the first registered one being
    *               kept in case of name conflict (i.e. the default data space one).
    ***/
    private static void registerTable(Map<String,TableConfig> tables, final TableConfig table) {
        if (table == null) return;
        String tableKey = table.name.toLowerCase();
        TableConfig existing = tables.get(tableKey);
        if (existing != null) {
            System.debug(LoggingLevel.WARN,'registerTable: ignoring DMO ' + table.dmoName + ' of data space ' + table.dataSpace
                + ' (table name ' + table.name + ' already used in data space ' + existing.dataSpace + ')');
            return;
        }
        tables.put(tableKey, table);
    }

    /***
    * @description  Returns the DMO names possibly matching a table name, i.e. with a
    *               namespace separator in place of its first underscore (e.g. ssot__), then
    *               without any namespace (e.g. data space prefixed DMOs such as spe_X_Y__dlm)
    *               and then with a namespace separator in place of each other underscore.
    ***/
    @TestVisible
    private static List<String> getDmoCandidates(final String tableName) {
        List<String> candidates = new List<String>();
        Integer index = tableName.indexOf('_');
        if (index > 0) candidates.add(tableName.left(index) + '__' + tableName.substring(index + 1) + DMO_SUFFIX);
        candidates.add(tableName + DMO_SUFFIX);
        if (index > 0) index = tableName.indexOf('_', index + 1);
        while (index > 0) {
            candidates.add(tableName.left(index) + '__' + tableName.substring(index + 1) + DMO_SUFFIX);
            index = tableName.indexOf('_', index + 1);
        }
        return candidates;
    }

    /***
    * @description  Returns the data spaces on which DMOs are fetched (loaded upon first
    *               call), i.e. the default data space first, then the other active data
    *               spaces accessible to the running user (alphabetical order).
    ***/
    @TestVisible
    private static List<String> getDataSpaces() {
        if (DATASPACES != null) return DATASPACES;
        List<String> dataSpaces = new List<String>{DEFAULT_DATASPACE};
        Set<String> dataSpaceKeys = new Set<String>{DEFAULT_DATASPACE};
        for (DataSpace iter : [SELECT DataSpaceApiName FROM DataSpace WHERE Status = 'ACTIVE' ORDER BY DataSpaceApiName]) {
            if ((String.isNotBlank(iter.DataSpaceApiName)) && (dataSpaceKeys.add(iter.DataSpaceApiName.toLowerCase()))) {
                dataSpaces.add(iter.DataSpaceApiName);
            }
        }
        DATASPACES = dataSpaces;
        System.debug('getDataSpaces: data spaces loaded ' + DATASPACES);
        return DATASPACES;
    }


    //#####################################################
    // Data 360 Metadata
    //#####################################################

    /***
    * @description  Fetches the metadata of all DMOs of a data space (or of a single DMO)
    *               via ConnectApi.CdpQuery.getAllMetadata() and returns them as untyped maps.
    *               The returned items being internal (Java) maps which cannot be used as
    *               Apex maps (instanceof Map<String,Object> returns true but any cast, map
    *               method or JSON.serialize() call raises an uncatchable system error), they
    *               are converted via their toString() representation (see parseMetadataItem).
    *               Mock items (test context) are true Apex maps and used as is (their
    *               toString() representation truncating lists beyond 10 elements).
    ***/
    @TestVisible
    private static List<Map<String,Object>> fetchMetadata(final String dataSpace, final String dmoName) {
        System.debug('fetchMetadata: START on data space ' + dataSpace + ' for DMO ' + dmoName);

        List<Map<String,Object>> results = new List<Map<String,Object>>();
        if (MOCK_METADATA != null) {
            List<Object> mockItems = MOCK_METADATA.get(dataSpace + '/' + (String.isBlank(dmoName) ? '*' : dmoName));
            if (mockItems != null) {
                for (Object iter : mockItems) results.add((Map<String,Object>) iter);
            }
            System.debug('fetchMetadata: END with #mock items ' + results.size());
            return results;
        }

        List<Object> items;
        try {
            ConnectApi.CdpQueryMetadataOutput output = ConnectApi.CdpQuery.getAllMetadata(DMO_ENTITY_TYPE, null, dmoName, dataSpace);
            items = (output == null) ? null : output.metadata;
        }
        catch (Exception e) {
            throw new DataSource.DataSourceException('Data 360 metadata fetch failed on data space ' + dataSpace
                + (String.isBlank(dmoName) ? '' : ' for DMO ' + dmoName) + ': ' + e.getMessage());
        }
        if (items == null) {
            System.debug('fetchMetadata: END with no metadata');
            return results;
        }

        for (Object iter : items) {
            String iterString = String.valueOf(iter);
            try {
                results.add(parseMetadataItem(iterString));
            }
            catch (Exception e) {
                // DMO ignored (e.g. unexpected special characters in a label)
                System.debug(LoggingLevel.WARN,'fetchMetadata: ignoring unparseable DMO metadata ' + iterString?.left(100) + ': ' + e.getMessage());
            }
        }
        System.debug('fetchMetadata: END with #items ' + results.size());
        return results;
    }

    /***
    * @description  Converts the toString() representation of a DMO metadata item, e.g.
    *               {name=ssot__Account__dlm, displayName=Account, fields=[{name=ssot__Id__c,
    *               type=STRING}, ...], indexes=[], ...} into an untyped map, by transforming
    *               it into JSON:
    *               - double quotes and backslashes (only possible in values) are escaped,
    *               - keys (identifiers followed by '=' after '{' or ',') are quoted,
    *               - scalar values (up to the next ', key=', '}' or ']') are quoted, commas
    *                 not followed by a key being kept as part of the value (e.g. in labels),
    *               - boolean, null and numeric values are unquoted.
    ***/
    @TestVisible
    private static Map<String,Object> parseMetadataItem(final String itemString) {
        String jsonString = itemString.replace('\\', '\\\\').replace('"', '\\"');
        jsonString = jsonString.replaceAll('([\\{,]\\s*)([A-Za-z0-9_]+)=', '$1"$2":');
        jsonString = jsonString.replaceAll(':(?![\\[\\{])(.*?)(?=, "[A-Za-z0-9_]+":|\\}|\\])', ':"$1"');
        jsonString = jsonString.replaceAll(':"(true|false|null|-?\\d+(?:\\.\\d+)?)"(?=[,\\}\\]])', ':$1');
        System.debug(LoggingLevel.FINEST,'parseMetadataItem: JSON metadata ' + jsonString);
        return (Map<String,Object>) JSON.deserializeUntyped(jsonString);
    }

    /***
    * @description  Returns the value of a metadata item property (case insensitive key).
    ***/
    @TestVisible
    private static Object getValue(final Map<String,Object> item, final String key) {
        if (item == null) return null;
        if (item.containsKey(key)) return item.get(key);
        for (String iter : item.keySet()) {
            if (iter.equalsIgnoreCase(key)) return item.get(iter);
        }
        return null;
    }

    private static String getString(final Map<String,Object> item, final String key) {
        Object value = getValue(item, key);
        return (value == null) ? null : String.valueOf(value);
    }

    private static List<Map<String,Object>> getList(final Map<String,Object> item, final String key) {
        List<Map<String,Object>> results = new List<Map<String,Object>>();
        Object value = getValue(item, key);
        if (value instanceof List<Object>) {
            for (Object iter : (List<Object>) value) {
                if (iter instanceof Map<String,Object>) results.add((Map<String,Object>) iter);
            }
        }
        return results;
    }

    /***
    * @description  Maps a Data 360 field type onto a connector data type.
    ***/
    @TestVisible
    private static String getDataType(final String dmoType) {
        switch on ((dmoType == null) ? '' : dmoType.toUpperCase().replace('_', '')) {
            when 'BOOLEAN' {
                return 'Boolean';
            }
            when 'NUMBER', 'NUMERIC', 'DECIMAL', 'DOUBLE', 'INTEGER', 'INT', 'BIGINT', 'LONG', 'CURRENCY', 'PERCENT' {
                return 'Number';
            }
            when 'DATE', 'DATETIME', 'TIMESTAMP', 'TIMESTAMPTZ' {
                return 'DateTime';
            }
            when 'URL' {
                return 'Url';
            }
            when else {
                return 'Text';
            }
        }
    }


    //#####################################################
    // SQL Execution
    //#####################################################

    /***
    * @description  Executes a SQL query synchronously via the sfsqlquery framework and returns
    *               the raw rows as lists of values (in the order of the selected columns).
    ***/
    @TestVisible
    private static List<List<Object>> executeSQL(final String sqlQuery, final String dataSpace) {
        System.debug('executeSQL: START on data space ' + dataSpace);
        System.debug(LoggingLevel.FINE,'executeSQL: with query ' + sqlQuery);

        sfsqlquery.SqlRowIterator queryIterator = sfsqlquery.SqlStatement.create(sqlQuery, dataSpace)
            .withWorkloadName(WORKLOAD)
            .execute();
        System.debug(LoggingLevel.FINE,'executeSQL: SQL query executed');

        List<List<Object>> results = new List<List<Object>>();
        List<ConnectApi.QuerySqlMetadataItem> queryMetadata;
        while (queryIterator.hasNext()) {
            sfsqlquery.Row iterRow = queryIterator.next();
            if (queryMetadata == null) {
                // Metadata only available once first page fetched
                queryMetadata = queryIterator.getMetadata();
                System.debug(LoggingLevel.FINEST,'executeSQL: metadata received ' + queryMetadata);
            }
            List<Object> iterValues = new List<Object>();
            for (Integer iterIndex = 0; iterIndex < queryMetadata.size(); iterIndex++) {
                iterValues.add(getFieldValue(iterRow, iterIndex, String.valueOf(queryMetadata.get(iterIndex).type)));
            }
            results.add(iterValues);
        }
        System.debug('executeSQL: END with #results ' + results.size());
        return results;
    }

    /***
    * @description  Extracts the value of a field from a sfsqlquery.Row via the typed getter
    *               matching the column type (date & time types being converted, other types
    *               returned as raw values).
    ***/
    @TestVisible
    private static Object getFieldValue(final sfsqlquery.Row row, final Integer index, final String fieldType) {
        switch on (fieldType?.toUpperCase()) {
            when 'DATE' {
                return row.getDate(index);
            }
            when 'TIMESTAMP', 'TIMESTAMPTZ' {
                return row.getDateTime(index);
            }
            when 'TIME' {
                return row.getTime(index);
            }
            when else {
                return row.getObject(index);
            }
        }
    }


    //#####################################################
    // Configuration Classes
    //#####################################################

    /***
    * @description  Configuration of a table exposed by the connector (i.e. a DMO).
    ***/
    public class TableConfig {
        public String name;
        public String label;
        public String pluralLabel;
        public String description;
        public String dmoName;
        public String dataSpace;
        public String nameColumn;
        public List<ColumnConfig> columns = new List<ColumnConfig>();
        private Map<String,ColumnConfig> columnMap = new Map<String,ColumnConfig>();

        /***
        * @description  Builds the table configuration from a DMO metadata item, DMO fields
        *               which cannot be exposed being ignored.
        ***/
        public TableConfig(final Map<String,Object> item, final String dataSpace) {
            this.dmoName = checkSqlName(getString(item, 'name'), 'DMO name');
            this.dataSpace = dataSpace;
            this.name = checkApiName(deriveName(this.dmoName, DMO_SUFFIX), 'table name of DMO ' + this.dmoName);
            String dmoLabel = getString(item, 'displayName');
            this.label = (String.isNotBlank(dmoLabel) ? dmoLabel : this.name).left(MAX_LABEL_LENGTH);
            this.pluralLabel = this.label;
            this.description = 'Data 360 DMO ' + this.dmoName + ' (data space ' + this.dataSpace + ')';

            // ExternalId systematically mapped to the DMO primary key, the mapped DMO field
            // being tracked in the column description.
            List<Map<String,Object>> primaryKeys = getList(item, 'primaryKeys');
            if (primaryKeys.size() != 1) {
                throw new DataSource.DataSourceException('No single primary key on DMO ' + this.dmoName);
            }
            String idField = getString(primaryKeys[0], 'name');
            String idLabel = getString(primaryKeys[0], 'displayName');
            ColumnConfig idColumn = new ColumnConfig(EXTERNAL_ID, checkSqlName(idField, 'Id field of DMO ' + this.dmoName));
            idColumn.description = 'Primary key of DMO ' + this.dmoName + ': ' + idField
                                 + (String.isBlank(idLabel) ? '' : ' (' + idLabel + ')');
            registerColumn(idColumn);
            registerColumn(new ColumnConfig(DISPLAY_URL, null));

            List<ColumnConfig> dmoColumns = new List<ColumnConfig>();
            for (Map<String,Object> iter : getList(item, 'fields')) {
                String iterName = getString(iter, 'name');
                if ((iterName != null) && (CURRENCY_FIELD_PATTERN.matcher(iterName).matches())) {
                    // Not added to the synced columns (CurrencyIsoCode being a standard field)
                    ColumnConfig currencyColumn = this.columnMap.get(CURRENCY_ISO_CODE.toLowerCase());
                    if (currencyColumn != null) {
                        System.debug(LoggingLevel.WARN,'TableConfig: ignoring currency field ' + iterName + ' of DMO ' + this.dmoName + ' (' + currencyColumn.dmoField + ' already used)');
                        continue;
                    }
                    System.debug(LoggingLevel.FINE,'TableConfig: mapping currency field ' + iterName + ' of DMO ' + this.dmoName + ' to ' + CURRENCY_ISO_CODE);
                    this.columnMap.put(CURRENCY_ISO_CODE.toLowerCase(), new ColumnConfig(CURRENCY_ISO_CODE, checkSqlName(iterName, 'DMO currency field')));
                    continue;
                }
                if ((iterName != null) && (iterName.startsWith(IGNORED_FIELD_PREFIX))) {
                    System.debug(LoggingLevel.FINE,'TableConfig: ignoring key qualifier field ' + iterName + ' of DMO ' + this.dmoName);
                    continue;
                }
                try {
                    dmoColumns.add(new ColumnConfig(iter));
                }
                catch (DataSource.DataSourceException e) {
                    System.debug(LoggingLevel.WARN,'TableConfig: ignoring field ' + iterName + ' of DMO ' + this.dmoName + ': ' + e.getMessage());
                }
            }
            dmoColumns.sort();
            for (ColumnConfig iter : dmoColumns) {
                if (this.columnMap.containsKey(iter.name.toLowerCase())) {
                    System.debug(LoggingLevel.WARN,'TableConfig: ignoring field ' + iter.dmoField + ' of DMO ' + this.dmoName + ' (column name ' + iter.name + ' already used)');
                    continue;
                }
                registerColumn(iter);
            }

            this.nameColumn = EXTERNAL_ID;
            for (ColumnConfig iter : this.columns) {
                if ((iter.dmoField != null) && (iter.dataType == 'Text') && (NAME_FIELD_PATTERN.matcher(iter.dmoField).matches())) {
                    this.nameColumn = iter.name;
                    break;
                }
            }
        }

        /***
        * @description  Returns the configuration of a column (exception raised if unknown).
        ***/
        public ColumnConfig getColumn(final String columnName) {
            ColumnConfig column = (columnName == null) ? null : this.columnMap.get(columnName.toLowerCase());
            if ((column == null) && (CURRENCY_ISO_CODE.equalsIgnoreCase(columnName))) {
                throw new DataSource.DataSourceException('Missing ' + CURRENCY_FIELD + ' (or CurrencyIsoCode__c) field on DMO ' + this.dmoName
                    + ' (required to provide the ' + CURRENCY_ISO_CODE + ' of table ' + this.name + ' in multi-currency Orgs)');
            }
            if (column == null) throw new DataSource.DataSourceException('Unknown column ' + columnName + ' on table ' + this.name);
            return column;
        }

        /***
        * @description  Returns the Connector Framework description of the table (for sync).
        ***/
        public DataSource.Table toTable() {
            List<DataSource.Column> tableColumns = new List<DataSource.Column>();
            for (ColumnConfig iter : this.columns) {
                tableColumns.add(iter.toColumn());
            }
            DataSource.Table table = DataSource.Table.get(this.name, this.nameColumn, tableColumns);
            table.labelSingular = this.label;
            table.labelPlural = this.pluralLabel;
            table.description = this.description;
            return table;
        }

        private void registerColumn(final ColumnConfig column) {
            String columnKey = column.name.toLowerCase();
            if (this.columnMap.containsKey(columnKey)) {
                throw new DataSource.DataSourceException('Column ' + column.name + ' configured multiple times on table ' + this.name);
            }
            this.columns.add(column);
            this.columnMap.put(columnKey, column);
        }
    }

    /***
    * @description  Configuration of a column exposed by the connector (i.e. a DMO field).
    ***/
    public class ColumnConfig implements Comparable {
        public String name;
        public String label;
        public String description;
        public String dmoField;
        public String dataType;
        public Integer length;
        public Integer decimalPlaces;
        public Boolean filterable = true;
        public Boolean sortable = true;

        /***
        * @description  Constructor for the standard ExternalId (mapped to the DMO Id field)
        *               and DisplayUrl (not mapped) columns.
        ***/
        public ColumnConfig(final String name, final String dmoField) {
            this.name = name;
            this.label = name;
            this.dmoField = dmoField;
            this.dataType = (name == DISPLAY_URL) ? 'Url' : 'Text';
            this.length = 255;
            this.filterable = (dmoField != null);
            this.sortable = (dmoField != null);
        }

        /***
        * @description  Constructor for DMO fields, from their metadata item.
        ***/
        public ColumnConfig(final Map<String,Object> field) {
            this.dmoField = checkSqlName(getString(field, 'name'), 'DMO field name');
            this.name = checkApiName(deriveName(this.dmoField, FIELD_SUFFIX), 'column name of DMO field ' + this.dmoField);
            if (RESERVED_COLUMNS.contains(this.name.toLowerCase())) {
                throw new DataSource.DataSourceException('Reserved column name ' + this.name + ' used for DMO field ' + this.dmoField);
            }
            String fieldLabel = getString(field, 'displayName');
            this.label = (String.isNotBlank(fieldLabel) ? fieldLabel : this.name).left(MAX_LABEL_LENGTH);
            this.dataType = getDataType(getString(field, 'type'));
            if (this.dataType == 'Number') this.decimalPlaces = DEFAULT_DECIMALS;
        }

        /***
        * @description  Returns the Connector Framework description of the column (for sync).
        ***/
        public DataSource.Column toColumn() {
            DataSource.DataType columnType;
            Integer columnLength = this.length;
            Integer columnDecimals = 0;
            switch on this.dataType {
                when 'Number' {
                    columnType = DataSource.DataType.NUMBER_TYPE;
                    if (columnLength == null) columnLength = 18;
                    columnDecimals = (this.decimalPlaces == null) ? 0 : this.decimalPlaces;
                }
                when 'Boolean' {
                    columnType = DataSource.DataType.BOOLEAN_TYPE;
                    columnLength = 0;
                }
                when 'DateTime' {
                    columnType = DataSource.DataType.DATETIME_TYPE;
                    columnLength = 0;
                }
                when 'Url' {
                    columnType = DataSource.DataType.URL_TYPE;
                }
                when else {
                    columnType = DataSource.DataType.STRING_SHORT_TYPE;
                }
            }
            if (columnLength == null) columnLength = 255;
            return DataSource.Column.get(this.name, this.label, this.description, this.sortable, this.filterable,
                                         columnType, columnLength, columnDecimals, null, null);
        }

        /***
        * @description  Converts a raw value returned by Data 360 into the type expected by
        *               the External Object column (text values being truncated to the
        *               column length).
        ***/
        public Object convert(final Object value) {
            if (value == null) return null;
            switch on this.dataType {
                when 'Number' {
                    return (value instanceof Decimal) ? value : Decimal.valueOf(String.valueOf(value));
                }
                when 'Boolean' {
                    return (value instanceof Boolean) ? value : Boolean.valueOf(String.valueOf(value));
                }
                when 'DateTime' {
                    // Date tested first (a Date being also an instance of Datetime in Apex)
                    if (value instanceof Date) return Datetime.newInstance((Date) value, Time.newInstance(0, 0, 0, 0));
                    return value;
                }
                when else {
                    // Date tested first (a Date being also an instance of Datetime in Apex)
                    String stringValue = (value instanceof Date) ? String.valueOf((Date) value)
                        : ((value instanceof Datetime) ? ((Datetime) value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'')
                        : String.valueOf(value));
                    if (this.dataType == 'Text') stringValue = stringValue.left((this.length == null) ? 255 : this.length);
                    return stringValue;
                }
            }
        }

        /***
        * @description  Sorts columns by name.
        ***/
        public Integer compareTo(Object other) {
            return this.name.compareTo(((ColumnConfig) other).name);
        }
    }


    //#####################################################
    // Private Utility Methods
    //#####################################################

    /***
    * @description  Derives a default table / column name from a DMO / field name, i.e.
    *               without suffix and with single underscores (e.g. ssot__Account__dlm
    *               exposed as ssot_Account).
    ***/
    @TestVisible
    private static String deriveName(final String name, final String suffix) {
        if (String.isBlank(name)) return name;
        String result = name.endsWithIgnoreCase(suffix) ? name.left(name.length() - suffix.length()) : name;
        result = result.replaceAll('[^A-Za-z0-9_]', '').replaceAll('_+', '_').removeStart('_').removeEnd('_');
        if ((result.length() > 0) && (!result.left(1).isAlpha())) result = 'X' + result;
        return result;
    }

    /***
    * @description  Checks that a table / column name is a valid Salesforce API name
    *               (without suffix).
    ***/
    @TestVisible
    private static String checkApiName(final String name, final String context) {
        if ((String.isBlank(name)) || (name.length() > MAX_NAME_LENGTH) || (!API_NAME_PATTERN.matcher(name).matches())) {
            throw new DataSource.DataSourceException('Invalid ' + context + ': ' + name);
        }
        return name;
    }

    /***
    * @description  Checks that a DMO / field name is a valid SQL identifier (to prevent
    *               any SQL injection via metadata).
    ***/
    @TestVisible
    private static String checkSqlName(final String name, final String context) {
        if ((String.isBlank(name)) || (!SQL_NAME_PATTERN.matcher(name).matches())) {
            throw new DataSource.DataSourceException('Invalid ' + context + ': ' + name);
        }
        return name;
    }
}
