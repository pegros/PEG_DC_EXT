/***
* @description  Test class for the Data 360 Apex Connector classes
*               (sfpegData360Provider, sfpegData360Connection, sfpegData360SqlBuilder),
*               Data 360 SQL responses being mocked via sfsqlquery.SqlTester, DMO
*               metadata via the MOCK_METADATA test hook (ConnectApi.CdpQuery not
*               being testable).
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

@SuppressWarnings('PMD.ClassNamingConventions')
@IsTest
public class sfpegData360Connector_TST {

	/***
	* @description  Test method for the sfpegData360Provider class (capabilities and connection).
	* @see          sfpegData360Provider
	***/

	@IsTest
	static void testProvider() {
		System.debug('testProvider: ##### START #####');

		Test.startTest();

		sfpegData360Provider provider = new sfpegData360Provider();
		Assert.areEqual(1, provider.getAuthenticationCapabilities().size(), 'Only one authentication capability should be supported');
		Assert.isTrue(provider.getCapabilities().contains(DataSource.Capability.ROW_QUERY), 'Row query capability should be supported');
		Assert.isFalse(provider.getCapabilities().contains(DataSource.Capability.ROW_CREATE), 'Row creation capability should not be supported');
		Assert.isTrue(provider.getConnection(new DataSource.ConnectionParams()) instanceof sfpegData360Connection, 'Connection should be a sfpegData360Connection');

		Test.stopTest();
		System.debug('testProvider: ##### END #####');
	}

	/***
	* @description  Test method for the sync() method, i.e. the DMO discovery from the Data 360
	*               metadata.
	* @see          sfpegData360Connection
	***/

	@IsTest
	static void testSync() {
		System.debug('testSync: ##### START #####');

		Test.startTest();

		System.debug('testSync: ##### TEST 1 - Sync of discovered DMOs #####');
		initDiscovery();
		sfpegData360Connection connection = new sfpegData360Connection(new DataSource.ConnectionParams());
		Map<String,DataSource.Table> tables = new Map<String,DataSource.Table>();
		for (DataSource.Table iter : connection.sync()) {
			tables.put(iter.name, iter);
		}
		System.debug('testSync: tables returned ' + tables.keySet());
		Assert.areEqual(new Set<String>{'ssot_Individual', 'ssot_Account', 'Sales', 'oth_Orders_Line'}, tables.keySet(),
			'DMOs of all data spaces should be returned, DMOs without single primary key or conflicting with the default data space being ignored');

		DataSource.Table individual = tables.get('ssot_Individual');
		Assert.areEqual('Individual', individual.labelSingular, 'DMO display name should be used as label');
		Assert.areEqual('Data 360 DMO ssot__Individual__dlm (data space default)', individual.description, 'Data space should be indicated in the table description');
		Assert.areEqual('Data 360 DMO oth_Orders_Line__dlm (data space other)', tables.get('oth_Orders_Line').description, 'Data space should be indicated in the table description');
		Assert.areEqual('ssot_Name', individual.nameColumn, 'Name field should be used as default name column');
		Map<String,DataSource.Column> columns = new Map<String,DataSource.Column>();
		for (DataSource.Column iter : individual.columns) {
			columns.put(iter.name, iter);
		}
		Assert.areEqual(new Set<String>{'ExternalId', 'DisplayUrl', 'ssot_Id', 'ssot_Name', 'ssot_BirthDate', 'Score', 'IsVip', 'Website'},
			columns.keySet(), 'Invalid, reserved, duplicate and key qualifier (KQ_) DMO fields should be ignored');
		Assert.areEqual('First Name', columns.get('ssot_Name').label, 'Field display name should be used as label');
		Assert.areEqual('Primary key of DMO ssot__Individual__dlm: ssot__Id__c (ssot__Id__c)', columns.get('ExternalId').description, 'ExternalId description should indicate the DMO primary key');
		Assert.areEqual(DataSource.DataType.STRING_SHORT_TYPE, columns.get('ssot_Name').type, 'String field should be exposed as text');
		Assert.areEqual(DataSource.DataType.DATETIME_TYPE, columns.get('ssot_BirthDate').type, 'Date field should be exposed as datetime');
		Assert.areEqual(DataSource.DataType.NUMBER_TYPE, columns.get('Score').type, 'Number field should be exposed as number');
		Assert.areEqual(4, columns.get('Score').decimalPlaces, 'Number field should have default decimals');
		Assert.areEqual(DataSource.DataType.BOOLEAN_TYPE, columns.get('IsVip').type, 'Boolean field should be exposed as boolean');
		Assert.areEqual(DataSource.DataType.URL_TYPE, columns.get('Website').type, 'Url field should be exposed as url');

		DataSource.Table account = tables.get('ssot_Account');
		Assert.areEqual('Account', account.labelPlural, 'DMO display name should be used as plural label');
		Assert.areEqual('ssot_Name', account.nameColumn, 'Name field should be used as default name column');
		Assert.areEqual('Primary key of DMO ssot__Account__dlm: ssot__Id__c (ssot__Id__c)', account.columns[0].description, 'ExternalId description should indicate the DMO primary key');
		Assert.areEqual(7, account.columns.size(), 'ExternalId, DisplayUrl and all DMO fields (except currency) should be returned');
		Assert.areEqual('Amount', account.columns[2].name, 'DMO columns should be sorted by name');
		Assert.areEqual('other', sfpegData360Connection.getTable('Sales').dataSpace, 'Data space of DMO should be used');
		Assert.areEqual('other', sfpegData360Connection.getTable('oth_Orders_Line').dataSpace, 'Data space of DMO should be used');
		Assert.areEqual('default', sfpegData360Connection.getTable('ssot_Individual').dataSpace, 'DMO of the default data space should take precedence in case of conflict');
		Assert.isNotNull(sfpegData360Connection.TABLES, 'Tables should be cached after full discovery');

		System.debug('testSync: ##### TEST 2 - Configuration errors #####');
		List<Map<String,Object>> validFields = new List<Map<String,Object>>{ initDmoField('ssot__Id__c', 'Id', 'STRING') };
		assertConfigError(initDmo('ssot__Account__dlm', 'Account', new List<String>(), validFields), 'missing primary key');
		assertConfigError(initDmo('ssot__Account__dlm', 'Account', new List<String>{'ssot__Id__c', 'Other__c'}, validFields), 'multiple primary keys');
		assertConfigError(initDmo('Bad DMO__dlm', 'Account', new List<String>{'ssot__Id__c'}, validFields), 'invalid DMO name');
		assertConfigError(initDmo('ssot__Account__dlm', 'Account', new List<String>{'ssot__Id__c OR 1=1'}, validFields), 'invalid primary key');

		Test.stopTest();
		System.debug('testSync: ##### END #####');
	}

	/***
	* @description  Test method for the table resolution at query time (without full discovery)
	*               and the naming / typing utilities.
	* @see          sfpegData360Connection
	***/

	@IsTest
	static void testResolve() {
		System.debug('testResolve: ##### START #####');

		Test.startTest();

		System.debug('testResolve: ##### TEST 1 - Real metadata fetch #####');
		try {
			sfpegData360Connection.fetchMetadata('default', 'ssot__Account__dlm');
		}
		catch (DataSource.DataSourceException e) {
			System.debug('testResolve: metadata not fetchable in test context ' + e.getMessage());
		}

		System.debug('testResolve: ##### TEST 2 - Targeted resolution #####');
		initDiscovery();
		Map<String,List<Object>> fullMetadata = sfpegData360Connection.MOCK_METADATA;
		sfpegData360Connection.MOCK_METADATA = new Map<String,List<Object>>{
			'default/ssot__Individual__dlm' => new List<Object>{ fullMetadata.get('default/*')[0] },
			'default/ssot__Account__dlm' => new List<Object>{ fullMetadata.get('default/*')[2] },
			'other/oth_Orders_Line__dlm' => new List<Object>{ fullMetadata.get('other/*')[2] }
		};
		Assert.areEqual('ssot__Individual__dlm', sfpegData360Connection.getTable('ssot_Individual').dmoName, 'Default table should be resolved from its derived DMO name');
		Assert.areEqual('ssot__Account__dlm', sfpegData360Connection.getTable('ssot_Account').dmoName, 'Namespaced table should be resolved from its derived DMO name');
		Assert.areEqual('other', sfpegData360Connection.getTable('oth_Orders_Line').dataSpace, 'Table of another data space should be resolved from its derived DMO name');
		Assert.isNull(sfpegData360Connection.TABLES, 'No full discovery should be done when tables are resolved');
		try {
			sfpegData360Connection.getTable('Unknown_Table');
			Assert.fail('Exception should be raised for unknown table');
		}
		catch (DataSource.DataSourceException e) {
			System.debug('testResolve: exception properly raised for unknown table ' + e.getMessage());
		}
		Assert.areEqual(new List<String>{'a__b_c__dlm', 'a_b_c__dlm', 'a_b__c__dlm'}, sfpegData360Connection.getDmoCandidates('a_b_c'),
			'DMO candidates should be properly derived from table name');
		Assert.areEqual(new List<String>{'abc__dlm'}, sfpegData360Connection.getDmoCandidates('abc'), 'DMO candidate of table name without underscore should be derived');

		System.debug('testResolve: ##### TEST 2b - Data spaces loading #####');
		sfpegData360Connection.DATASPACES = null;
		List<String> dataSpaces = sfpegData360Connection.getDataSpaces();
		System.debug('testResolve: data spaces loaded ' + dataSpaces);
		Assert.areEqual('default', dataSpaces[0], 'Default data space should be returned first');
		Assert.areEqual(dataSpaces.size(), new Set<String>(dataSpaces).size(), 'Data spaces should not be duplicated');

		System.debug('testResolve: ##### TEST 3 - Naming and typing utilities #####');
		Assert.areEqual('ssot_Account', sfpegData360Connection.deriveName('ssot__Account__dlm', '__dlm'), 'Namespace separator and suffix should be removed');
		Assert.areEqual('X1Field', sfpegData360Connection.deriveName('_1Field__c', '__c'), 'Name should start with a letter');
		Assert.areEqual('Number', sfpegData360Connection.getDataType('Number'), 'Number type should be mapped');
		Assert.areEqual('DateTime', sfpegData360Connection.getDataType('DATE_TIME'), 'DateTime type should be mapped');
		Assert.areEqual('Text', sfpegData360Connection.getDataType('EMAIL'), 'Other types should be mapped as text');
		Assert.areEqual('Text', sfpegData360Connection.getDataType(null), 'Missing type should be mapped as text');
		Assert.areEqual('x', sfpegData360Connection.getValue(new Map<String,Object>{'NAME' => 'x'}, 'name'), 'Property keys should be case insensitive');

		System.debug('testResolve: ##### TEST 4 - Metadata item parsing #####');
		// toString() format of the (Java) map items returned by ConnectApi.CdpQuery.getAllMetadata()
		Map<String,Object> parsedItem = sfpegData360Connection.parseMetadataItem(
			'{fields=[{name=ssot__Id__c, displayName=Account Id, type=STRING, keyQualifier=KQ_Id__c, businessType=TEXT}, '
			+ '{name=ssot__Name__c, displayName=Name, "Legal" a=b \\ test, type=STRING, businessType=TEXT}], '
			+ 'indexes=[], category=Profile, name=ssot__Account__dlm, displayName=, isActive=true, '
			+ 'primaryKeys=[{name=ssot__Id__c, displayName=Account Id, indexOrder=1}], referenceModelEntityDeveloperName=Account}');
		Assert.areEqual('ssot__Account__dlm', parsedItem.get('name'), 'DMO name should be parsed');
		Assert.areEqual('', parsedItem.get('displayName'), 'Empty values should be parsed');
		Assert.areEqual(true, parsedItem.get('isActive'), 'Boolean values should be parsed');
		Assert.areEqual(0, ((List<Object>) parsedItem.get('indexes')).size(), 'Empty lists should be parsed');
		List<Object> parsedFields = (List<Object>) parsedItem.get('fields');
		Assert.areEqual(2, parsedFields.size(), 'All DMO fields should be parsed');
		Assert.areEqual('Name, "Legal" a=b \\ test', ((Map<String,Object>) parsedFields[1]).get('displayName'), 'Special characters should be kept in values');
		Assert.areEqual(1, ((Map<String,Object>) ((List<Object>) parsedItem.get('primaryKeys'))[0]).get('indexOrder'), 'Numeric values should be parsed');

		Test.stopTest();
		System.debug('testResolve: ##### END #####');
	}

	/***
	* @description  Test method for the SQL generation of the sfpegData360SqlBuilder class
	*               (columns, filters, order, paging and count).
	* @see          sfpegData360SqlBuilder
	***/

	@IsTest
	static void testSqlBuilder() {
		System.debug('testSqlBuilder: ##### START #####');

		Test.startTest();

		initTables();
		sfpegData360Connection.TableConfig table = sfpegData360Connection.getTable('ssot_account');
		sfpegData360SqlBuilder builder = new sfpegData360SqlBuilder(table);

		System.debug('testSqlBuilder: ##### TEST 1 - Select without filter #####');
		DataSource.TableSelection selection = initSelection(new List<String>(), null, null);
		Assert.areEqual('SELECT ssot__Id__c, Amount__c, IsActive__c, ssot__ContactId__c, ssot__CreatedDate__c, ssot__Name__c FROM ssot__Account__dlm LIMIT 2000',
			builder.buildSelect(selection, null, null), 'All columns should be selected when no column is specified');

		System.debug('testSqlBuilder: ##### TEST 2 - Select with filters, order and paging #####');
		selection = initSelection(
			new List<String>{'ssot_Name', 'Amount', 'DisplayUrl'},
			initGroup(DataSource.FilterType.AND_, new List<DataSource.Filter>{
				initFilter(DataSource.FilterType.EQUALS, 'ssot_Name', 'O\'Maley'),
				initFilter(DataSource.FilterType.GREATER_THAN, 'Amount', 1000.5),
				initGroup(DataSource.FilterType.OR_, new List<DataSource.Filter>{
					initFilter(DataSource.FilterType.CONTAINS, 'ssot_Name', '50%_off'),
					initFilter(DataSource.FilterType.NOT_EQUALS, 'IsActive', true)
				}),
				initGroup(DataSource.FilterType.NOT_, new List<DataSource.Filter>{
					initFilter(DataSource.FilterType.EQUALS, 'ssot_CreatedDate', null)
				})
			}),
			new List<DataSource.Order>{ initOrder('Amount', DataSource.OrderDirection.DESCENDING) });
		Assert.areEqual('SELECT ssot__Id__c, ssot__Name__c, Amount__c FROM ssot__Account__dlm'
			+ ' WHERE (ssot__Name__c = \'O\'\'Maley\') AND (Amount__c > 1000.5)'
			+ ' AND ((ssot__Name__c ILIKE \'%50\\%\\_off%\') OR ((IsActive__c <> TRUE OR IsActive__c IS NULL)))'
			+ ' AND (NOT (ssot__CreatedDate__c IS NULL))'
			+ ' ORDER BY Amount__c DESC NULLS LAST LIMIT 10 OFFSET 20',
			builder.buildSelect(selection, 10, 20), 'Filters, order and paging should be properly translated');

		System.debug('testSqlBuilder: ##### TEST 3 - Default order when paging #####');
		selection = initSelection(new List<String>{'ExternalId'}, null, null);
		Assert.areEqual('SELECT ssot__Id__c FROM ssot__Account__dlm ORDER BY ssot__Id__c ASC LIMIT 10 OFFSET 10',
			builder.buildSelect(selection, 10, 10), 'ExternalId should be used as default order when paging');

		System.debug('testSqlBuilder: ##### TEST 4 - Count query #####');
		selection = initSelection(new List<String>{'ExternalId'},
			initFilter(DataSource.FilterType.STARTS_WITH, 'ssot_Name', 'Acme'), null);
		selection.columnsSelected[0].aggregation = DataSource.QueryAggregation.COUNT;
		Assert.isTrue(sfpegData360SqlBuilder.isCount(selection), 'Count query should be detected');
		Assert.areEqual('SELECT COUNT(*) FROM ssot__Account__dlm WHERE ssot__Name__c ILIKE \'Acme%\'',
			builder.buildCount(selection), 'Count query should be properly built');

		System.debug('testSqlBuilder: ##### TEST 5 - Other conditions #####');
		Assert.areEqual('ssot__Name__c ILIKE \'%corp\'', builder.buildFilter(initFilter(DataSource.FilterType.ENDS_WITH, 'ssot_Name', 'corp')), 'ENDS_WITH should be translated');
		Assert.areEqual('ssot__Name__c ILIKE \'A%c_\'', builder.buildFilter(initFilter(DataSource.FilterType.LIKE_, 'ssot_Name', 'A%c_')), 'LIKE should be translated');
		Assert.areEqual('Amount__c <= 12', builder.buildFilter(initFilter(DataSource.FilterType.LESS_THAN_OR_EQUAL_TO, 'Amount', '12')), 'String value on Number column should be parsed');
		Assert.areEqual('Amount__c >= 5', builder.buildFilter(initFilter(DataSource.FilterType.GREATER_THAN_OR_EQUAL_TO, 'Amount', 5)), 'Integer value should be formatted');
		Assert.areEqual('IsActive__c = FALSE', builder.buildFilter(initFilter(DataSource.FilterType.EQUALS, 'IsActive', 'false')), 'String value on Boolean column should be parsed');
		Assert.areEqual('ssot__CreatedDate__c < TIMESTAMP \'2026-01-02 03:04:05\'',
			builder.buildFilter(initFilter(DataSource.FilterType.LESS_THAN, 'ssot_CreatedDate', Datetime.newInstanceGmt(2026, 1, 2, 3, 4, 5))), 'Datetime value should be formatted');
		Assert.areEqual('ssot__CreatedDate__c < DATE \'2026-01-02\'',
			builder.buildFilter(initFilter(DataSource.FilterType.LESS_THAN, 'ssot_CreatedDate', Date.newInstance(2026, 1, 2))), 'Date value should be formatted');
		Assert.areEqual('ssot__Id__c IS NOT NULL', builder.buildFilter(initFilter(DataSource.FilterType.NOT_EQUALS, 'ExternalId', null)), 'Null inequality should be translated');

		System.debug('testSqlBuilder: ##### TEST 5b - Multi-currency CurrencyIsoCode column #####');
		String currencyQuery = builder.buildSelect(initSelection(new List<String>{'ssot_Name', 'CurrencyIsoCode'}, null, null), 10, 0);
		Assert.isTrue(currencyQuery.startsWith('SELECT ssot__Id__c, ssot__Name__c, cdp_sys_record_currency__c FROM'), 'CurrencyIsoCode should be mapped to the DMO currency field');
		Map<String,Object> currencyRow = builder.mapRow(new List<Object>{ 'ID1', 'Acme', 'EUR' });
		Assert.areEqual('Acme', currencyRow.get('ssot_Name'), 'Mapped columns should be returned');
		Assert.areEqual('EUR', currencyRow.get('CurrencyIsoCode'), 'Record currency should be returned for CurrencyIsoCode');
		Assert.areEqual('cdp_sys_record_currency__c = \'EUR\'', builder.buildFilter(initFilter(DataSource.FilterType.EQUALS, 'CurrencyIsoCode', 'EUR')), 'CurrencyIsoCode filter should be translated');
		try {
			new sfpegData360SqlBuilder(new sfpegData360Connection.TableConfig(initDmo('ssot__Individual__dlm', 'Individual', new List<String>{'ssot__Id__c'},
				new List<Map<String,Object>>{ initDmoField('ssot__Id__c', 'Id', 'STRING') }), 'default')).buildSelect(initSelection(new List<String>{'CurrencyIsoCode'}, null, null), 10, 0);
			Assert.fail('Exception should be raised for CurrencyIsoCode on DMO without currency field');
		}
		catch (DataSource.DataSourceException e) {
			Assert.isTrue(e.getMessage().contains('Missing cdp_sys_record_currency__c (or CurrencyIsoCode__c) field on DMO ssot__Individual__dlm'), 'Missing currency field should be indicated: ' + e.getMessage());
		}

		System.debug('testSqlBuilder: ##### TEST 6 - Error cases #####');
		assertBuildError(builder, initFilter(DataSource.FilterType.EQUALS, 'Amount', '1 OR 1=1'), 'SQL injection attempt on Number column');
		assertBuildError(builder, initFilter(DataSource.FilterType.EQUALS, 'Unknown', 'x'), 'unknown column');
		assertBuildError(builder, initFilter(DataSource.FilterType.EQUALS, 'DisplayUrl', 'x'), 'unmapped column');
		assertBuildError(builder, initGroup(DataSource.FilterType.NOT_, new List<DataSource.Filter>()), 'empty NOT filter');
		assertBuildError(builder, initGroup(DataSource.FilterType.AND_, new List<DataSource.Filter>()), 'empty AND filter');
		try {
			builder.buildSelect(initSelection(new List<String>{'ssot_Name'}, null,
				new List<DataSource.Order>{ initOrder('DisplayUrl', DataSource.OrderDirection.ASCENDING) }), 10, 0);
			Assert.fail('Exception should be raised when sorting on an unmapped column');
		}
		catch (DataSource.DataSourceException e) {
			System.debug('testSqlBuilder: exception properly raised when sorting on an unmapped column ' + e.getMessage());
		}

		Test.stopTest();
		System.debug('testSqlBuilder: ##### END #####');
	}

	/***
	* @description  Test method for the query() method of the sfpegData360Connection class
	*               (Data 360 responses being mocked via sfsqlquery.SqlTester).
	* @see          sfpegData360Connection
	***/

	@IsTest
	static void testQuery() {
		System.debug('testQuery: ##### START #####');

		Test.startTest();

		initTables();
		sfpegData360Connection connection = new sfpegData360Connection(new DataSource.ConnectionParams());

		System.debug('testQuery: ##### TEST 1 - Select query #####');
		sfsqlquery.SqlTester.clearMocks();
		sfsqlquery.SqlTester.setMockMetadata(new List<ConnectApi.QuerySqlMetadataItem>{
			initColumn('ssot__Id__c', ConnectApi.TypeEnum.Varchar),
			initColumn('ssot__Name__c', ConnectApi.TypeEnum.Varchar),
			initColumn('Amount__c', ConnectApi.TypeEnum.Numeric),
			initColumn('IsActive__c', ConnectApi.TypeEnum.Varchar)
		});
		sfsqlquery.SqlTester.setMockRows(new List<ConnectApi.QuerySqlRow>{
			initRow(new List<Object>{'ID001', 'Name001', 1000.00, 'true'}),
			initRow(new List<Object>{'ID002', null, 25, 'false'})
		});
		DataSource.QueryContext context = new DataSource.QueryContext();
		context.tableSelection = initSelection(new List<String>{'ssot_Name', 'Amount', 'IsActive', 'DisplayUrl'}, null, null);
		context.maxResults = 10;
		context.offset = 0;
		DataSource.TableResult result = connection.query(context);
		System.debug('testQuery: result returned ' + result);
		Assert.areEqual(2, result.rows.size(), '2 rows should be returned');
		Assert.areEqual('ID001', result.rows[0].get('ExternalId'), 'ExternalId should be properly mapped');
		Assert.areEqual('Name001', result.rows[0].get('ssot_Name'), 'Text column should be properly mapped');
		Assert.areEqual(1000.00, (Decimal) result.rows[0].get('Amount'), 'Number column should be properly mapped');
		Assert.areEqual(true, result.rows[0].get('IsActive'), 'Boolean column should be converted');
		Assert.isNull(result.rows[0].get('DisplayUrl'), 'DisplayUrl should be null');
		Assert.isNull(result.rows[1].get('ssot_Name'), 'Null values should be kept');
		Assert.areEqual(25, ((Decimal) result.rows[1].get('Amount')).intValue(),'Integer values should be converted to Decimal');

		System.debug('testQuery: ##### TEST 2 - Count query #####');
		sfsqlquery.SqlTester.clearMocks();
		sfsqlquery.SqlTester.setMockMetadata(new List<ConnectApi.QuerySqlMetadataItem>{
			initColumn('count', ConnectApi.TypeEnum.Numeric)
		});
		sfsqlquery.SqlTester.setMockRows(new List<ConnectApi.QuerySqlRow>{
			initRow(new List<Object>{42})
		});
		context = new DataSource.QueryContext();
		context.tableSelection = initSelection(new List<String>{'ExternalId'}, null, null);
		context.tableSelection.columnsSelected[0].aggregation = DataSource.QueryAggregation.COUNT;
		result = connection.query(context);
		Assert.areEqual(42, result.rows[0].get('ExternalId'), 'Count should be properly returned');

		System.debug('testQuery: ##### TEST 3 - Unknown table #####');
		context = new DataSource.QueryContext();
		context.tableSelection = initSelection(new List<String>{'ExternalId'}, null, null);
		context.tableSelection.tableSelected = 'Unknown';
		try {
			connection.query(context);
			Assert.fail('Exception should be raised for unknown table');
		}
		catch (DataSource.DataSourceException e) {
			System.debug('testQuery: exception properly raised for unknown table ' + e.getMessage());
		}

		System.debug('testQuery: ##### TEST 4 - Search #####');
		DataSource.SearchContext searchContext = new DataSource.SearchContext();
		searchContext.searchPhrase = 'Name';
		searchContext.tableSelections = new List<DataSource.TableSelection>();
		try {
			List<DataSource.TableResult> searchResults = connection.search(searchContext);
			Assert.areEqual(0, searchResults.size(), 'No result should be returned when no table is searched');
		}
		catch (Exception e) {
			System.debug('testQuery: search not executable in test context ' + e.getMessage());
		}

		Test.stopTest();
		System.debug('testQuery: ##### END #####');
	}

	/***
	* @description  Test method for the value conversions of the ColumnConfig class.
	* @see          sfpegData360Connection
	***/

	@IsTest
	static void testConvert() {
		System.debug('testConvert: ##### START #####');

		Test.startTest();

		initTables();
		sfpegData360Connection.TableConfig table = sfpegData360Connection.getTable('ssot_Account');
		Datetime testDT = Datetime.newInstanceGmt(2026, 1, 2, 3, 4, 5);

		Assert.areEqual(testDT, table.getColumn('ssot_CreatedDate').convert(testDT), 'Datetime should be kept for DateTime columns');
		Assert.areEqual(Datetime.newInstance(2026, 1, 2), table.getColumn('ssot_CreatedDate').convert(Date.newInstance(2026, 1, 2)), 'Date should be converted for DateTime columns');
		Assert.areEqual('2026-01-02T03:04:05.000Z', table.getColumn('ssot_Name').convert(testDT), 'Datetime should be formatted for Text columns');
		Assert.areEqual('12', table.getColumn('ssot_Name').convert(12), 'Number should be converted for Text columns');
		Assert.areEqual(12.5, table.getColumn('Amount').convert('12.5'), 'String should be parsed for Number columns');
		Assert.areEqual(true, table.getColumn('IsActive').convert(true), 'Boolean should be kept for Boolean columns');

		Test.stopTest();
		System.debug('testConvert: ##### END #####');
	}


	//#####################################################
	// Private Utility Methods
	//#####################################################

	private static void initTables() {
		sfpegData360Connection.TableConfig table = new sfpegData360Connection.TableConfig(initAccountDmo(), 'default');
		sfpegData360Connection.TABLES = new Map<String,sfpegData360Connection.TableConfig>{
			table.name.toLowerCase() => table
		};
	}

	private static void initDiscovery() {
		sfpegData360Connection.DATASPACES = new List<String>{'default', 'other'};

		sfpegData360Connection.MOCK_METADATA = new Map<String,List<Object>>{
			'default/*' => new List<Object>{
				initDmo('ssot__Individual__dlm', 'Individual', new List<String>{'ssot__Id__c'}, new List<Map<String,Object>>{
					initDmoField('ssot__Id__c', 'Individual Id', 'STRING'),
					initDmoField('ssot__Name__c', 'First Name', 'STRING'),
					initDmoField('ssot__BirthDate__c', 'Birth Date', 'DATE'),
					initDmoField('Score__c', 'Score', 'NUMBER'),
					initDmoField('IsVip__c', 'VIP', 'BOOLEAN'),
					initDmoField('Website__c', 'Website', 'URL'),
					initDmoField('KQ_Id__c', 'Key Qualifier', 'STRING'),
					initDmoField('IsVip___c', 'Duplicate', 'BOOLEAN'),
					initDmoField('Bad Field', 'Invalid', 'STRING'),
					initDmoField('Id__c', 'Reserved', 'STRING')
				}),
				initDmo('NoKey__dlm', 'No Key', new List<String>(), new List<Map<String,Object>>{
					initDmoField('Name__c', 'Name', 'STRING')
				}),
				initAccountDmo()
			},
			'other/*' => new List<Object>{
				initDmo('Sales__dlm', 'Sales', new List<String>{'Id__c'}, new List<Map<String,Object>>{
					initDmoField('Id__c', 'Id', 'STRING')
				}),
				initDmo('ssot__Individual__dlm', 'Other Individual', new List<String>{'ssot__Id__c'}, new List<Map<String,Object>>{
					initDmoField('ssot__Id__c', 'Individual Id', 'STRING')
				}),
				initDmo('oth_Orders_Line__dlm', 'Order Line', new List<String>{'Id__c'}, new List<Map<String,Object>>{
					initDmoField('Id__c', 'Id', 'STRING')
				})
			}
		};
	}

	private static Map<String,Object> initAccountDmo() {
		return initDmo('ssot__Account__dlm', 'Account', new List<String>{'ssot__Id__c'}, new List<Map<String,Object>>{
			initDmoField('ssot__CreatedDate__c', 'Created Date', 'DATE_TIME'),
			initDmoField('Amount__c', 'Amount', 'NUMBER'),
			initDmoField('ssot__Name__c', 'Name', 'STRING'),
			initDmoField('ssot__ContactId__c', 'Contact', 'STRING'),
			initDmoField('IsActive__c', 'Active', 'BOOLEAN'),
			initDmoField('cdp_sys_record_currency__c', 'Record Currency', 'STRING'),
			initDmoField('CurrencyIsoCode__c', 'Duplicate Currency', 'STRING')
		});
	}

	private static Map<String,Object> initDmo(final String name, final String displayName, final List<String> primaryKeys, final List<Map<String,Object>> fields) {
		List<Object> keys = new List<Object>();
		for (String iter : primaryKeys) {
			keys.add(new Map<String,Object>{ 'name' => iter, 'displayName' => iter, 'indexOrder' => String.valueOf(keys.size() + 1) });
		}
		return new Map<String,Object>{
			'name' => name, 'displayName' => displayName, 'category' => 'Profile',
			'primaryKeys' => keys, 'fields' => fields
		};
	}

	private static Map<String,Object> initDmoField(final String name, final String displayName, final String type) {
		return new Map<String,Object>{ 'name' => name, 'displayName' => displayName, 'type' => type };
	}

	private static void assertConfigError(final Map<String,Object> dmo, final String errorCase) {
		try {
			new sfpegData360Connection.TableConfig(dmo, 'default');
			Assert.fail('Exception should be raised for ' + errorCase);
		}
		catch (DataSource.DataSourceException e) {
			System.debug('assertConfigError: exception properly raised for ' + errorCase + ': ' + e.getMessage());
		}
	}

	private static void assertBuildError(final sfpegData360SqlBuilder builder, final DataSource.Filter filter, final String errorCase) {
		try {
			builder.buildFilter(filter);
			Assert.fail('Exception should be raised for ' + errorCase);
		}
		catch (Exception e) {
			Assert.isFalse(e instanceof AssertException, 'Exception should be raised for ' + errorCase);
			System.debug('assertBuildError: exception properly raised for ' + errorCase + ': ' + e.getMessage());
		}
	}

	private static DataSource.TableSelection initSelection(final List<String> columns, final DataSource.Filter filter, final List<DataSource.Order> orders) {
		DataSource.TableSelection selection = new DataSource.TableSelection();
		selection.tableSelected = 'ssot_Account';
		selection.columnsSelected = new List<DataSource.ColumnSelection>();
		for (String iter : columns) {
			DataSource.ColumnSelection iterColumn = new DataSource.ColumnSelection();
			iterColumn.columnName = iter;
			iterColumn.tableName = 'ssot_Account';
			iterColumn.aggregation = DataSource.QueryAggregation.NONE;
			selection.columnsSelected.add(iterColumn);
		}
		selection.filter = filter;
		selection.order = orders;
		return selection;
	}

	private static DataSource.Filter initFilter(final DataSource.FilterType type, final String columnName, final Object value) {
		DataSource.Filter filter = new DataSource.Filter();
		filter.type = type;
		filter.columnName = columnName;
		filter.columnValue = value;
		filter.tableName = 'ssot_Account';
		return filter;
	}

	private static DataSource.Filter initGroup(final DataSource.FilterType type, final List<DataSource.Filter> subfilters) {
		DataSource.Filter filter = new DataSource.Filter();
		filter.type = type;
		filter.subfilters = subfilters;
		return filter;
	}

	private static DataSource.Order initOrder(final String columnName, final DataSource.OrderDirection direction) {
		DataSource.Order order = new DataSource.Order();
		order.columnName = columnName;
		order.direction = direction;
		order.tableName = 'ssot_Account';
		return order;
	}

	private static ConnectApi.QuerySqlMetadataItem initColumn(final String name, final ConnectApi.TypeEnum type) {
		ConnectApi.QuerySqlMetadataItem column = new ConnectApi.QuerySqlMetadataItem();
		column.name = name;
		column.type = type;
		return column;
	}

	private static ConnectApi.QuerySqlRow initRow(final List<Object> values) {
		ConnectApi.QuerySqlRow row = new ConnectApi.QuerySqlRow();
		row.row = values;
		return row;
	}
}
