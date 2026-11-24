# ![Logo](/media/Logo.png) &nbsp; SFPEG **DC EXT** Components


## Introduction

This package contains a set of tools to extend standard **Data360** capabilities
and better access **Data360** configuration and data.

These components were built as contributions or examples for former and ongoing Advisory assignments by 
[Pierre-Emmanuel Gros](https://github.com/pegros). 

ℹ️ Additional Data360 utilities may also be found in the **[PEG_LIST_DC](https://github.com/pegros/PEG_LIST_DC)** and  **[PEG_DC](https://github.com/pegros/PEG_LIST_DC)** repositories


## Repository Content

This repository contains a whole set of tools dedicated to **Data360** management:
* the **[sfpegData360Connector](/help/sfpegData360Connector.md)** custom Apex external connector, enabling to map DMOs as
read-only External Objects and display them easily within
Salesforce Lightning applications.
* the **[sfpegRichTextDisplay](/help/sfpegRichTextDisplay.md)** Lightning Web Component, enabling
to display a rich text field of an (External Object) record page with the look & feel of a
standard read-only output field.

ℹ️ All are located in dedicated folders (`external` for eth Apex utility and `display` for the LWC component)
so that they be easily deployed independently.

## Installation

ℹ️ As the **ConnectApi** Apex class induces multiple implicit dependencies requiring **Data Cloud**
specific features on scratch Orgs, it is currently impossible to distribute the content of this
repository as an **unlocked package**.

⚠️ **Data360** should be active on your Org when you deploy this package and applicable
permissions granted to your user.

The following two options are therefore available for package installation:
* **Git** and **SF CLI** Deployment
* **Quick Direct Deploy** button


### **Git** and **SF CLI** Deployment

To retrieve the SFDX project, you may simply execute a git clone from the GitHub repository.
```
git clone git@github.com:pegros/PEG_DC_EXT.git
```

Via SFDX you may then deploy it on you Org
```
sfdx force:source:deploy -u <yourOrgAlias> -w 10 --verbose -p force-app
```

### Quick Direct Deploy

For a quick and easy deployment, you may alternatively use the following deploy button
leveraging the **[GitHub Salesforce Deploy Tool](https://github.com/afawcett/githubsfdeploy)**
implemented by [Andrew Fawcett](https://andyinthecloud.com/2013/09/24/deploy-direct-from-github-to-salesforce/).

To deploy only the whole package to your Org, you may use the following button.

<a href="https://githubsfdeploy.herokuapp.com?ref=master">
  <img alt="Deploy Package to Salesforce"
       src="https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png">
</a>


## Release Notes

ℹ️ As this repository is not distributed as **unlocked package**, there is no real
package version. This section however summarizes the timeline and contents of the main
evolutions made.

### November 2026

First version of the package.
* Initialisation of the **[sfpegData360Connector](/help/sfpegData360Connector.md)** custom
Apex connector for _Salesforce Connect_ (a.k.a. _External Objects_).
* Initialization of the **[sfpegRichTextDisplay](/help/sfpegRichTextDisplay.md)** LWC
component to force _richText_ field display of such fields not supported by _External Objects_.

