/***
* @description  Apex Connector Framework provider class enabling to expose Data 360
*               DMOs as (read-only) Salesforce Connect External Objects, queries
*               being executed via the sfsqlquery framework.
*               It should be selected as type of the External Data Source.
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
global with sharing class sfpegData360Provider extends DataSource.Provider {

    /***
    * @description  No authentication required, Data 360 being queried locally
    *               (no callout) on behalf of the running user.
    ***/
    override global List<DataSource.AuthenticationCapability> getAuthenticationCapabilities() {
        return new List<DataSource.AuthenticationCapability>{
            DataSource.AuthenticationCapability.ANONYMOUS
        };
    }

    /***
    * @description  Read-only connector, supporting SOQL queries and SOSL searches
    *               (on the name column of the External Objects).
    ***/
    override global List<DataSource.Capability> getCapabilities() {
        return new List<DataSource.Capability>{
            DataSource.Capability.ROW_QUERY,
            DataSource.Capability.SEARCH
        };
    }

    /***
    * @description  Returns the connection actually implementing the sync, query
    *               and search operations.
    ***/
    override global DataSource.Connection getConnection(DataSource.ConnectionParams connectionParams) {
        return new sfpegData360Connection(connectionParams);
    }
}
