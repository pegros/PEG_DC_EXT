/***
* @description  LWC displaying a rich text field of the current record (e.g. an
*               External Object exposed via the Data 360 connector) via the
*               standard lightning-formatted-rich-text base component.
*               The field to display is configured in the App Builder, the record
*               context (recordId, objectApiName) being provided by the page.
*               Part of the PEG_DC package external connector.
* @author       P-E GROS
* @date         November 2026
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

import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

export default class SfpegRichTextDisplay extends LightningElement {

    //----------------------------------------------------------------
    // Configuration parameters (App Builder)
    //----------------------------------------------------------------
    @api fieldName;         // API name of the rich text field to display (e.g. Description__c)
    @api wrappingClass = 'slds-theme_default'; // CSS classes for the wrapping div
    @api fieldLabel;        // Optional label override (field label from object metadata by default)
    @api isDebug = false;   // Debug mode activation

    //----------------------------------------------------------------
    // Context parameters (page)
    //----------------------------------------------------------------
    @api recordId;
    @api objectApiName;

    //----------------------------------------------------------------
    // Internal state
    //----------------------------------------------------------------
    record;
    objectInfo;
    errorMessage;
    isLoaded = false;

    //----------------------------------------------------------------
    // Custom getters
    //----------------------------------------------------------------
    get fullFieldName() {
        if (!this.fieldName || !this.objectApiName) return undefined;
        const field = this.fieldName.trim();
        // supports both "Field__c" and "Object__x.Field__c" configurations
        return field.includes('.') ? field : `${this.objectApiName}.${field}`;
    }
    get shortFieldName() {
        return this.fullFieldName ? this.fullFieldName.split('.').pop() : undefined;
    }
    get fields() {
        return this.fullFieldName ? [this.fullFieldName] : undefined;
    }
    get fieldValue() {
        return this.record ? getFieldValue(this.record, this.fullFieldName) : undefined;
    }
    get displayLabel() {
        if (this.fieldLabel) return this.fieldLabel;
        const fieldDesc = this.objectInfo?.fields?.[this.shortFieldName];
        return fieldDesc?.label || this.shortFieldName || '';
    }
    get configError() {
        if (!this.fieldName) return 'Missing field name in component configuration.';
        return undefined;
    }

    //----------------------------------------------------------------
    // Data fetch
    //----------------------------------------------------------------
    @wire(getObjectInfo, { objectApiName: '$objectApiName' })
    wiredObjectInfo({ data, error }) {
        if (data) {
            this.objectInfo = data;
            if (this.isDebug) console.log('wiredObjectInfo: END OK for ', this.objectApiName);
        }
        else if (error) {
            // non blocking: label falls back to the field API name
            this.objectInfo = undefined;
            if (this.isDebug) console.warn('wiredObjectInfo: END KO with ', JSON.stringify(error));
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: '$fields' })
    wiredRecord({ data, error }) {
        if (this.isDebug) console.log('wiredRecord: START for ', this.fullFieldName, ' on ', this.recordId);
        if (data) {
            this.record = data;
            this.errorMessage = undefined;
            this.isLoaded = true;
            if (this.isDebug) console.log('wiredRecord: END OK with ', JSON.stringify(data));
        }
        else if (error) {
            this.record = undefined;
            this.errorMessage = this.formatError(error);
            this.isLoaded = true;
            if (this.isDebug) console.warn('wiredRecord: END KO with ', JSON.stringify(error));
        }
    }

    //----------------------------------------------------------------
    // Utilities
    //----------------------------------------------------------------
    formatError(error) {
        if (!error) return 'Unknown error';
        if (Array.isArray(error.body)) return error.body.map(item => item.message).join(', ');
        if (error.body && error.body.message) return error.body.message;
        if (error.message) return error.message;
        return JSON.stringify(error);
    }
}
