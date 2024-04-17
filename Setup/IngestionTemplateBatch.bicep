@description('The name of the storage account. It must be unique across all existing storage account names in Azure, between 3 and 24 characters long, and can contain only lowercase letters and numbers.')
param StorageAccount string

@allowed([
  'ar-BH | Arabic (Bahrain)'
  'ar-EG | Arabic (Egypt)'
  'ar-SY | Arabic (Syria)'
  'ca-ES | Catalan'
  'da-DK | Danish (Denmark)'
  'de-DE | German (Germany)'
  'en-AU | English (Australia)'
  'en-CA | English (Canada)'
  'en-GB | English (United Kingdom)'
  'en-IN | English (India)'
  'en-NZ | English (New Zealand)'
  'en-US | English (United States)'
  'es-ES | Spanish (Spain)'
  'es-MX | Spanish (Mexico)'
  'fi-FI | Finnish (Finland)'
  'fr-CA | French (Canada)'
  'fr-FR | French (France)'
  'gu-IN | Gujarati (Indian)'
  'hi-IN | Hindi (India)'
  'it-IT | Italian (Italy)'
  'ja-JP | Japanese (Japan)'
  'ko-KR | Korean (Korea)'
  'mr-IN | Marathi (India)'
  'nb-NO | Norwegian (Bokmål)'
  'nl-NL | Dutch (Netherlands)'
  'pl-PL | Polish (Poland)'
  'pt-BR | Portuguese (Brazil)'
  'pt-PT | Portuguese (Portugal)'
  'ru-RU | Russian (Russia)'
  'sv-SE | Swedish (Sweden)'
  'ta-IN | Tamil (India)'
  'te-IN | Telugu (India)'
  'th-TH | Thai (Thailand)'
  'tr-TR | Turkish (Turkey)'
  'zh-CN | Chinese (Mandarin, simplified)'
  'zh-HK | Chinese (Cantonese, Traditional)'
  'zh-TW | Chinese (Taiwanese Mandarin)'
])
param Locale string = 'en-US | English (United States)'

@description('The id of the custom model for transcription. If empty, the base model will be selected.')
param CustomModelId string = ''

@description('The key for the Azure Speech Services subscription.')
@secure()
param AzureSpeechServicesKey string

@description('The region the Azure speech services subscription is associated with.')
@allowed([
  'centralus'
  'eastus2'
])
param AzureSpeechServicesRegion string = 'eastus2'

@description('Enter the address of your private endpoint here (e.g. https://mycustomendpoint.cognitiveservices.azure.com/) if you are connecting with a private endpoint')
param CustomEndpoint string = ''

@description('The requested profanity filter mode.')
@allowed([
  'None'
  'Removed'
  'Tags'
  'Masked'
])
param ProfanityFilterMode string = 'None'

@description('The requested punctuation mode.')
@allowed([
  'None'
  'Dictated'
  'Automatic'
  'DictatedAndAutomatic'
])
param PunctuationMode string = 'DictatedAndAutomatic'

@description('A value indicating whether diarization (speaker separation) is requested.')
param AddDiarization bool = false

@description('A value indicating whether word level timestamps are requested.')
param AddWordLevelTimestamps bool = false

@description('The key for the Text Analytics subscription.')
@secure()
param TextAnalyticsKey string = ''

@description('The endpoint the Text Analytics subscription is associated with (format should be like https://{resourceName}.cognitiveservices.azure.com or https://{region}.api.cognitive.microsoft.com or similar). If empty, no text analysis will be performed.')
param TextAnalyticsEndpoint string = ''

@description('A value indicating whether sentiment analysis is requested (either per utterance or per audio). Will only be performed if a Text Analytics Key and Region is provided.')
@allowed([
  'None'
  'UtteranceLevel'
  'AudioLevel'
])
param SentimentAnalysis string = 'None'

@description('A value indicating whether personally identifiable information (PII) redaction is requested. Will only be performed if a Text Analytics Key and Region is provided.')
@allowed([
  'None'
  'UtteranceAndAudioLevel'
])
param PiiRedaction string = 'None'

@description('The administrator username of the SQL Server, which is used to gain insights of the audio with the provided PowerBI scripts. If it is left empty, no SQL server/database will be created.')
param SqlAdministratorLogin string = ''

@description('The administrator password of the SQL Server. If it is left empty, no SQL server/database will be created.')
@secure()
param SqlAdministratorLoginPassword string = ''

// @description('Id that will be suffixed to all created resources to identify resources of a certain deployment. Leave as is to use timestamp as deployment id.')
// param DeploymentId string = utcNow()

param ResourceGroupLocation string = resourceGroup().location

@description('BYOS allows for the speech service to utilize an internal storage account')
param IsByosEnabledSubscription bool = false

@description('DB connection used for transcription analytics')
param AzureSqlDBConnection string

var Version = 'v2.0.12'
var AudioInputContainer = 'audio-input'
var AudioProcessedContainer = 'audio-processed'
var ErrorFilesOutputContainer = 'audio-failed'
var JsonResultOutputContainer = 'json-result-output'
var HtmlResultOutputContainer = 'html-result-output'
var ErrorReportOutputContainer = 'error-report'
var ConsolidatedFilesOutputContainer = 'consolidated-files'
var CreateHtmlResultFile = false
var CreateConsolidatedOutputFiles = false
var TimerBasedExecution = true
var CreateAudioProcessedContainer = true
var MessagesPerFunctionExecution = 1000
var FilesPerTranscriptionJob = 100
var RetryLimit = 4
var InitialPollingDelayInMinutes = 2
var MaxPollingDelayInMinutes = 180
var InstanceId = uniqueString(resourceGroup().id)
var StorageAccountName = StorageAccount
var UseSqlDatabase = ((SqlAdministratorLogin != '') && (SqlAdministratorLoginPassword != ''))
var SqlServerName = 'sqlserver${toLower(InstanceId)}'
var DatabaseName = 'Database-${toLower(InstanceId)}'
var ServiceBusName = 'ServiceBus-${InstanceId}'
var AppInsightsName = 'AppInsights-${InstanceId}'
var KeyVaultName = 'KV-${InstanceId}'
var EventGridSystemTopicName = '${StorageAccountName}-${InstanceId}'
var StartTranscriptionFunctionName = take('StartTranscriptionFunction-${InstanceId}', 60)
var StartTranscriptionFunctionId = StartTranscriptionFunction.id
var FetchTranscriptionFunctionName = take('FetchTranscriptionFunction-${InstanceId}', 60)
var FetchTranscriptionFunctionId = FetchTranscriptionFunction.id
var AppServicePlanName = 'AppServicePlan-${InstanceId}'
var AzureSpeechServicesKeySecretName = 'AzureSpeechServicesKey'
var TextAnalyticsKeySecretName = 'TextAnalyticsKey'
var DatabaseConnectionStringSecretName = 'DatabaseConnectionString'
var PiiCategories = ''
var ConversationPiiCategories = ''
var ConversationPiiRedaction = 'None'
var ConversationPiiInferenceSource = 'text'
var ConversationSummarizationOptions = '{"Stratergy":{"Key":"Channel","Mapping":{"0":"Agent","1":"Customer"},"FallbackRole":"None"},"Aspects":["Issue","Resolution","ChapterTitle","Narrative"],"Enabled":false,"InputLengthLimit":125000}'
var IsAzureGovDeployment = ((AzureSpeechServicesRegion == 'usgovarizona') || (AzureSpeechServicesRegion == 'usgovvirginia'))
var AzureSpeechServicesEndpointUri = ((CustomEndpoint != '')
  ? CustomEndpoint
  : (IsAzureGovDeployment
      ? 'https://${AzureSpeechServicesRegion}.api.cognitive.microsoft.us/'
      : 'https://${AzureSpeechServicesRegion}.api.cognitive.microsoft.com/'))
var EndpointSuffix = (IsAzureGovDeployment ? 'core.usgovcloudapi.net' : environment().suffixes.storage)
var BinariesRoutePrefix = 'https://github.com/Azure-Samples/cognitive-services-speech-sdk/releases/download/ingestion-'
var StartTranscriptionByTimerBinary = '${BinariesRoutePrefix}${Version}/StartTranscriptionByTimer.zip'
var StartTranscriptionByServiceBusBinary = '${BinariesRoutePrefix}${Version}/StartTranscriptionByServiceBus.zip'
var FetchTranscriptionBinary = '${BinariesRoutePrefix}${Version}/FetchTranscription.zip'



resource AppInsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: AppInsightsName
  location: ResourceGroupLocation
  tags: {
    applicationType: 'web'
    applicationName: 'TranscriptionInsights'
  }
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource ServiceBus 'Microsoft.ServiceBus/namespaces@2018-01-01-preview' = {
  name: ServiceBusName
  location: ResourceGroupLocation
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    zoneRedundant: false
  }
}

resource KeyVault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: KeyVaultName
  location: ResourceGroupLocation
  properties: {
    enabledForDeployment: true
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        objectId: reference(StartTranscriptionFunction.id, '2019-08-01', 'full').identity.principalId
        tenantId: reference(StartTranscriptionFunction.id, '2019-08-01', 'full').identity.tenantId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
      {
        objectId: reference(FetchTranscriptionFunction.id, '2019-08-01', 'full').identity.principalId
        tenantId: reference(FetchTranscriptionFunction.id, '2019-08-01', 'full').identity.tenantId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource KeyVaultName_AzureSpeechServicesKeySecret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  parent: KeyVault
  name: AzureSpeechServicesKeySecretName
  properties: {
    value: AzureSpeechServicesKey
  }
}

resource KeyVaultName_TextAnalyticsKeySecret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  parent: KeyVault
  name: TextAnalyticsKeySecretName
  properties: {
    value: (empty(TextAnalyticsKey) ? 'NULL' : TextAnalyticsKey)
  }
}

resource KeyVaultName_DatabaseConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  parent: KeyVault
  name: DatabaseConnectionStringSecretName
  properties: {
    value: (UseSqlDatabase
      ? 'Server=tcp:${reference(SqlServerName,'2014-04-01-preview').fullyQualifiedDomainName},1433;Initial Catalog=${DatabaseName};Persist Security Info=False;User ID=${SqlAdministratorLogin};Password=${SqlAdministratorLoginPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
      : 'NULL')
  }
  dependsOn: [
    SqlServer
  ]
}

resource SqlServer 'Microsoft.Sql/servers@2021-02-01-preview' =
  if (UseSqlDatabase) {
    name: SqlServerName
    location: ResourceGroupLocation
    tags: {
      displayName: 'SqlServer'
    }
    properties: {
      administratorLogin: SqlAdministratorLogin
      administratorLoginPassword: SqlAdministratorLoginPassword
      version: '12.0'
    }
  }

resource SqlServerName_Database 'Microsoft.Sql/servers/databases@2015-01-01' =
  if (UseSqlDatabase) {
    parent: SqlServer
    name: DatabaseName
    location: ResourceGroupLocation
    tags: {
      displayName: 'Database'
    }
    properties: {
      edition: 'Basic'
      collation: 'SQL_Latin1_General_CP1_CI_AS'
      requestedServiceObjectiveName: 'Basic'
    }
  }

resource SqlServerName_DatabaseName_current 'Microsoft.Sql/servers/databases/transparentDataEncryption@2014-04-01-preview' =
  if (UseSqlDatabase) {
    parent: SqlServerName_Database
    name: 'current'
    location: ResourceGroupLocation
    properties: {
      status: 'Enabled'
    }
  }

resource SqlServerName_DefaultAuditingSettings 'Microsoft.Sql/servers/auditingSettings@2017-03-01-preview' =
  if (UseSqlDatabase) {
    parent: SqlServer
    name: 'DefaultAuditingSettings'
    properties: {
      state: 'Enabled'
      storageEndpoint: reference(StorageAccount_resource.id, '2018-03-01-preview').PrimaryEndpoints.Blob
      storageAccountAccessKey: listKeys(StorageAccount_resource.id, '2018-03-01-preview').keys[0].value
      storageAccountSubscriptionId: subscription().subscriptionId
      auditActionsAndGroups: null
      isStorageSecondaryKeyInUse: false
    }
  }

resource SqlServerName_AllowAllMicrosoftAzureIps 'Microsoft.Sql/servers/firewallrules@2014-04-01' =
  if (UseSqlDatabase) {
    parent: SqlServer
    name: 'AllowAllMicrosoftAzureIps'
    properties: {
      endIpAddress: '0.0.0.0'
      startIpAddress: '0.0.0.0'
    }
  }

resource StorageAccount_resource 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: StorageAccountName
  location: ResourceGroupLocation
  sku: {
    name: 'Standard_GRS'
  }
  kind: 'StorageV2'
  properties: {
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

resource ServiceBusName_RootManageSharedAccessKey 'Microsoft.ServiceBus/namespaces/authorizationRules@2017-04-01' = {
  parent: ServiceBus
  name: 'RootManageSharedAccessKey'
  properties: {
    rights: [
      'Listen'
      'Manage'
      'Send'
    ]
  }
}

resource ServiceBusName_start_transcription_queue 'Microsoft.ServiceBus/namespaces/queues@2017-04-01' = {
  parent: ServiceBus
  name: 'start_transcription_queue'
  properties: {
    lockDuration: 'PT4M'
    maxSizeInMegabytes: 5120
    requiresDuplicateDetection: false
    requiresSession: false
    defaultMessageTimeToLive: 'P10675199DT2H48M5.4775807S'
    deadLetteringOnMessageExpiration: false
    enableBatchedOperations: false
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    maxDeliveryCount: 1
    status: 'Active'
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    enablePartitioning: false
    enableExpress: false
  }
}

resource ServiceBusName_fetch_transcription_queue 'Microsoft.ServiceBus/namespaces/queues@2017-04-01' = {
  parent: ServiceBus
  name: 'fetch_transcription_queue'
  properties: {
    lockDuration: 'PT5M'
    maxSizeInMegabytes: 5120
    requiresDuplicateDetection: false
    requiresSession: false
    defaultMessageTimeToLive: 'P10675199DT2H48M5.4775807S'
    deadLetteringOnMessageExpiration: false
    enableBatchedOperations: false
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    maxDeliveryCount: 5
    status: 'Active'
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    enablePartitioning: false
    enableExpress: false
  }
}

resource StorageAccountName_default 'Microsoft.Storage/storageAccounts/blobServices@2019-06-01' = {
  parent: StorageAccount_resource
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: false
    }
  }
}

resource Microsoft_Storage_storageAccounts_fileServices_StorageAccountName_default 'Microsoft.Storage/storageAccounts/fileServices@2019-06-01' = {
  parent: StorageAccount_resource
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

resource ServiceBusName_fetch_transcription_queue_FetchTranscription 'Microsoft.ServiceBus/namespaces/queues/authorizationRules@2017-04-01' = {
  parent: ServiceBusName_fetch_transcription_queue
  name: 'FetchTranscription'
  properties: {
    rights: [
      'Listen'
      'Send'
    ]
  }
  dependsOn: [
    ServiceBusName_RootManageSharedAccessKey
  ]
}

resource ServiceBusName_start_transcription_queue_StartTranscription 'Microsoft.ServiceBus/namespaces/queues/authorizationRules@2017-04-01' = {
  parent: ServiceBusName_start_transcription_queue
  name: 'StartTranscription'
  properties: {
    rights: [
      'Listen'
      'Send'
    ]
  }
  dependsOn: [
    ServiceBusName_RootManageSharedAccessKey
  ]
}

resource StorageAccountName_default_AudioInputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  parent: StorageAccountName_default
  name: AudioInputContainer
  properties: {
    publicAccess: 'None'
  }
  
}

resource StorageAccountName_default_JsonResultOutputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  parent: StorageAccountName_default
  name: JsonResultOutputContainer
  properties: {
    publicAccess: 'None'
  }
}

resource StorageAccountName_default_ConsolidatedFilesOutputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' =
  if (CreateConsolidatedOutputFiles) {
    parent: StorageAccountName_default
    name: ConsolidatedFilesOutputContainer
    properties: {
      publicAccess: 'None'
    }
  }

resource StorageAccountName_default_AudioProcessedContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' =
  if (CreateAudioProcessedContainer) {
    parent: StorageAccountName_default
    name: AudioProcessedContainer
    properties: {
      publicAccess: 'None'
    }
  }

resource StorageAccountName_default_HtmlResultOutputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' =
  if (CreateHtmlResultFile) {
    parent: StorageAccountName_default
    name: HtmlResultOutputContainer
    properties: {
      publicAccess: 'None'
    }
  }

resource StorageAccountName_default_ErrorReportOutputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  parent: StorageAccountName_default
  name: ErrorReportOutputContainer
  properties: {
    publicAccess: 'None'
  }
}

resource StorageAccountName_default_ErrorFilesOutputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  parent: StorageAccountName_default
  name: ErrorFilesOutputContainer
  properties: {
    publicAccess: 'None'
  }
}

resource EventGridSystemTopic 'Microsoft.EventGrid/systemTopics@2020-04-01-preview' = {
  name: EventGridSystemTopicName
  location: ResourceGroupLocation
  properties: {
    source: StorageAccount_resource.id
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
  dependsOn: [
    StorageAccountName_default
  ]
}

resource EventGridSystemTopicName_BlobCreatedEvent 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2020-04-01-preview' = {
  parent: EventGridSystemTopic
  name: 'BlobCreatedEvent'
  properties: {
    destination: {
      endpointType: 'ServiceBusQueue'
      properties: {
        resourceId: resourceId('Microsoft.ServiceBus/namespaces/queues', ServiceBusName, 'start_transcription_queue')
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      advancedFilters: [
        {
          operatorType: 'StringBeginsWith'
          key: 'Subject'
          values: [
            '/blobServices/default/containers/${AudioInputContainer}/blobs'
          ]
        }
        {
          operatorType: 'StringContains'
          key: 'data.api'
          values: [
            'FlushWithClose'
            'PutBlob'
            'PutBlockList'
            'CopyBlob'
          ]
        }
      ]
    }
    labels: []
    eventDeliverySchema: 'EventGridSchema'
  }
  dependsOn: [
    StorageAccountName_default
    StorageAccount_resource
    ServiceBusName_start_transcription_queue
  ]
}

resource AppServicePlan 'Microsoft.Web/serverfarms@2018-02-01' = {
  kind: 'app'
  name: AppServicePlanName
  location: ResourceGroupLocation
  properties: {}
  sku: {
    name: 'EP1'
  }
  dependsOn: []
}

resource StartTranscriptionFunction 'Microsoft.Web/sites@2020-09-01' = {
  name: StartTranscriptionFunctionName
  location: ResourceGroupLocation
  kind: 'functionapp'
  properties: {
    serverFarmId: AppServicePlan.id
    httpsOnly: true
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource StartTranscriptionFunctionName_AppSettings 'Microsoft.Web/sites/config@2020-09-01' = {
  parent: StartTranscriptionFunction
  name: 'appsettings'
  properties: {
    AddDiarization: '${AddDiarization}'
    AddWordLevelTimestamps: '${AddWordLevelTimestamps}'
    APPLICATIONINSIGHTS_CONNECTION_STRING: AppInsights.properties.ConnectionString
    AudioInputContainer: AudioInputContainer
    AzureServiceBus: ServiceBusName_RootManageSharedAccessKey.listKeys().primaryConnectionString
    AzureSpeechServicesKey: '@Microsoft.KeyVault(VaultName=${KeyVaultName};SecretName=${AzureSpeechServicesKeySecretName})'
    AzureSpeechServicesRegion: AzureSpeechServicesRegion
   // AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${StorageAccountName};AccountKey=${listKeys(StorageAccount_resource.id,providers('Microsoft.Storage','storageAccounts').apiVersions[0]).keys[0].value};EndpointSuffix=${EndpointSuffix}'
    //AzureWebJobsDashboard: 'DefaultEndpointsProtocol=https;AccountName=${StorageAccountName};AccountKey=${listKeys(StorageAccount_resource.id,providers('Microsoft.Storage','storageAccounts').apiVersions[0]).keys[0].value};EndpointSuffix=${EndpointSuffix}'
    AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${StorageAccountName};AccountKey=${listKeys(StorageAccount_resource.id, '2021-04-01').keys[0].value};EndpointSuffix=${EndpointSuffix}'
    CustomModelId: CustomModelId
    ErrorFilesOutputContainer: ErrorFilesOutputContainer
    ErrorReportOutputContainer: ErrorReportOutputContainer
    FetchTranscriptionServiceBusConnectionString: ServiceBusName_fetch_transcription_queue_FetchTranscription.listKeys().primaryConnectionString
    FilesPerTranscriptionJob: '${FilesPerTranscriptionJob}'
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: 'dotnet'
    AzureSpeechServicesEndpointUri: AzureSpeechServicesEndpointUri
    InitialPollingDelayInMinutes: '${InitialPollingDelayInMinutes}'
    IsAzureGovDeployment: '${IsAzureGovDeployment}'
    IsByosEnabledSubscription: '${IsByosEnabledSubscription}'
    MaxPollingDelayInMinutes: '${MaxPollingDelayInMinutes}'
    Locale: Locale
    MessagesPerFunctionExecution: '${MessagesPerFunctionExecution}'
    ProfanityFilterMode: ProfanityFilterMode
    PunctuationMode: PunctuationMode
    RetryLimit: '${RetryLimit}'
    StartTranscriptionServiceBusConnectionString: ServiceBusName_start_transcription_queue_StartTranscription.listKeys().primaryConnectionString
    WEBSITE_RUN_FROM_PACKAGE: (TimerBasedExecution
      ? StartTranscriptionByTimerBinary
      : StartTranscriptionByServiceBusBinary)
  }
  dependsOn: [
    KeyVault
    KeyVaultName_AzureSpeechServicesKeySecret
  ]
}

resource FetchTranscriptionFunction 'Microsoft.Web/sites@2020-09-01' = {
  name: FetchTranscriptionFunctionName
  location: ResourceGroupLocation
  kind: 'functionapp'
  properties: {
    serverFarmId: AppServicePlan.id
    httpsOnly: true
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource FetchTranscriptionFunctionName_AppSettings 'Microsoft.Web/sites/config@2020-09-01' = {
  parent: FetchTranscriptionFunction
  name: 'appsettings'
  properties: {
    APPLICATIONINSIGHTS_CONNECTION_STRING: AppInsights.properties.ConnectionString
    PiiRedactionSetting: PiiRedaction
    SentimentAnalysisSetting: SentimentAnalysis
    AudioInputContainer: AudioInputContainer
    AzureServiceBus: ServiceBusName_RootManageSharedAccessKey.listKeys().primaryConnectionString
    AzureSpeechServicesKey: '@Microsoft.KeyVault(VaultName=${KeyVaultName};SecretName=${AzureSpeechServicesKeySecretName})'
    //AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${StorageAccountName};AccountKey=${listKeys(StorageAccount_resource.id,providers('Microsoft.Storage','storageAccounts').apiVersions[0]).keys[0].value};EndpointSuffix=${EndpointSuffix}'
    //AzureWebJobsDashboard: 'DefaultEndpointsProtocol=https;AccountName=${StorageAccountName};AccountKey=${listKeys(StorageAccount_resource.id,providers('Microsoft.Storage','storageAccounts').apiVersions[0]).keys[0].value};EndpointSuffix=${EndpointSuffix}'
    AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${StorageAccountName};AccountKey=${listKeys(StorageAccount_resource.id,'2021-04-01').keys[0].value};EndpointSuffix=${EndpointSuffix}'
    CreateHtmlResultFile:  '${CreateHtmlResultFile}'
    DatabaseConnectionString: '@Microsoft.KeyVault(VaultName=${KeyVaultName};SecretName=${DatabaseConnectionStringSecretName})'
    ErrorFilesOutputContainer: ErrorFilesOutputContainer
    ErrorReportOutputContainer: ErrorReportOutputContainer
    FetchTranscriptionServiceBusConnectionString: ServiceBusName_fetch_transcription_queue_FetchTranscription.listKeys().primaryConnectionString
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: 'dotnet'
    HtmlResultOutputContainer: HtmlResultOutputContainer
    InitialPollingDelayInMinutes: '${InitialPollingDelayInMinutes}'
    MaxPollingDelayInMinutes: '${MaxPollingDelayInMinutes}'
    JsonResultOutputContainer: JsonResultOutputContainer
    RetryLimit: '${RetryLimit}'
    StartTranscriptionServiceBusConnectionString: ServiceBusName_start_transcription_queue_StartTranscription.listKeys().primaryConnectionString
    TextAnalyticsKey: '@Microsoft.KeyVault(VaultName=${KeyVaultName};SecretName=${TextAnalyticsKeySecretName})'
    TextAnalyticsEndpoint: TextAnalyticsEndpoint
    UseSqlDatabase: '${UseSqlDatabase}'
    WEBSITE_RUN_FROM_PACKAGE: FetchTranscriptionBinary
    CreateConsolidatedOutputFiles: '${CreateConsolidatedOutputFiles}'
    ConsolidatedFilesOutputContainer: ConsolidatedFilesOutputContainer
    CreateAudioProcessedContainer: '${CreateAudioProcessedContainer}'
    AudioProcessedContainer: AudioProcessedContainer
    PiiCategories: PiiCategories
    ConversationPiiCategories: ConversationPiiCategories
    ConversationPiiInferenceSource: ConversationPiiInferenceSource
    ConversationPiiSetting: ConversationPiiRedaction
    ConversationSummarizationOptions: ConversationSummarizationOptions
  }
  dependsOn: [
    KeyVault
    KeyVaultName_AzureSpeechServicesKeySecret
    KeyVaultName_TextAnalyticsKeySecret
  ]
}

output StartTranscriptionFunctionId string = StartTranscriptionFunctionId
output FetchTranscriptionFunctionId string = FetchTranscriptionFunctionId
