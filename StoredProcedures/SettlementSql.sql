CREATE PROCEDURE [dbo].[SettlementSql]
	@TenantId int,
	@CreateDate datetime2,
	@Language int
AS
BEGIN

;WITH CTE_SettlementRawData AS 
(
	SELECT *
	FROM [dbo].[ReportData]
	WHERE ( ReportId = 10 OR 
	ReportId = 11 OR ReportId = 12) 
	AND CreateDate = @CreateDate
)

,CTE_SettlementFinal AS (
SELECT * FROM (
	SELECT JSON_VALUE(value, '$.TypRozrachunku')						AS TypRozrachunku
	,JSON_VALUE(value, '$.Numer')										AS Numer
	,JSON_VALUE(value, '$.Symbol')										AS Symbol
	,JSON_VALUE(value, '$.Kontrahent')									AS Kontrahent
	,JSON_VALUE(value, '$.DataFaktury')									AS DataFaktury
	,JSON_VALUE(value, '$.DataEwidencji')								AS DataEwidencji
	,JSON_VALUE(value, '$.TerminPlatnosci')								AS TerminPlatnosci
	,CAST(JSON_VALUE(value, '$.Zwloka') AS int)							AS Zwloka
	,CAST(JSON_VALUE(value, '$.Pozostalo') AS int)						AS Pozostalo
	,JSON_VALUE(value, '$.DataRozliczenia')								AS DataRozliczenia
	,CAST(JSON_VALUE(value, '$.KwotaFaktury') AS decimal(18,2))			AS KwotaFaktury
	,JSON_VALUE(value, '$.WalutaFaktury')								AS WalutaFaktury
	,CAST(JSON_VALUE(value, '$.Naleznosc') AS decimal(18,2))			AS Naleznosc
	,CAST(JSON_VALUE(value, '$.Zobowiazanie') AS decimal(18,2))			AS Zobowiazanie
	,CAST(JSON_VALUE(value, '$.Saldo') AS decimal(18,2))				AS Saldo
	,JSON_VALUE(value, '$.SaldoWaluta')									AS SaldoWaluta
	,CAST(JSON_VALUE(value, '$.KwotaRozliczona') AS decimal(18,2))		AS KwotaRozliczona
	,JSON_VALUE(value, '$.KwotaRozliczonaWaluta')						AS KwotaRozliczonaWaluta
	,CAST(JSON_VALUE(value, '$.DoRozliczenia') AS decimal(18,2))		AS DoRozliczenia
	,JSON_VALUE(value, '$.DoRozliczeniaWaluta')							AS DoRozliczeniaWaluta
	,CAST(JSON_VALUE(value, '$.DoRozliczeniaPLN') AS decimal(18,2))		AS DoRozliczeniaPLN
	,JSON_VALUE(value, '$.Opis')										AS Opis
	,JSON_VALUE(value, '$.ZaplataZa')									AS ZaplataZa
	,CAST(JSON_VALUE(value, '$.SaldoRozrachunku') AS decimal(18,2))		AS SaldoRozrachunku
	,CAST(JSON_VALUE(value, '$.SaldoKonta') AS decimal(18,2))			AS SaldoKonta
	,CAST(JSON_VALUE(value, '$.Difference') AS decimal(18,2))			AS [Difference]
	,CAST(JSON_VALUE(value, '$.Id') AS INT)								AS Id
	FROM CTE_SettlementRawData
		CTE_SettlementRawData CROSS APPLY OPENJSON (CTE_SettlementRawData.[Data]) as jv) AS Data
)
	
--SELECT * FROM CTE_SettlementRawData
--SELECT * FROM CTE_SettlementFinal
--ORDER BY Id DESC, Symbol ASC

SELECT DISTINCT
	9 AS ReportId,
	(
		SELECT DISTINCT *
		FROM CTE_SettlementFinal
		ORDER BY Id DESC, Symbol ASC
		FOR JSON PATH
	) AS [Data]
		
	OPTION(RECOMPILE)
END
GO