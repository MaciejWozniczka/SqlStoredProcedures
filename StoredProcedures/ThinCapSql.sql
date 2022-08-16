CREATE PROCEDURE [dbo].[ThinCapSql]
	@TenantId int,
	@CreateDate datetime2
AS

BEGIN

IF(OBJECT_ID('tempdb..#TCPositions') Is Not Null)
	BEGIN
		DROP TABLE #TCPositions
	END
		
;WITH  
CTE_TenantAccounts
AS
(
SELECT
[Id] ,[Node], Symbol
FROM
[dbo].[Accounts]
WHERE
TenantId = @TenantId
	AND Accounts.Type = 'Wynikowe'
),

CTE_TenantAccounts_leafes AS (
	SELECT child.[Node] ,child.[Id] ,child.Symbol
	FROM CTE_TenantAccounts AS child
	LEFT OUTER JOIN CTE_TenantAccounts AS parent
	ON child.[Node] = parent.[Node].GetAncestor(1)
	WHERE parent.[Node] IS NULL
),

CTE_MapEntriesByDate
AS
(
SELECT
MAX([Id]) as Id
,MAX([CreateDate]) as CreateDate
,[AccountId]
--,[MapEntryId]
FROM
[dbo].[TrialBalanceMapEntries]
WHERE
CreateDate <= @CreateDate
GROUP BY AccountId
),

CTE_CurrentMapEntriesByTenant
AS
(
SELECT
	m.Id
	,m.CreateDate
	,m.AccountId
	,t.Symbol
FROM
CTE_MapEntriesByDate m
JOIN
CTE_TenantAccounts_leafes t
ON
m.AccountId = t.Id
),

CTE_CurrentMapEntriesByTenantWithData
AS
(
SELECT
	t.Id
	,t.CreateDate
	,t.AccountId
	,c.Symbol
	,m.[Data]
FROM
[dbo].[TrialBalanceMapEntries] t
JOIN
CTE_CurrentMapEntriesByTenant c
ON
t.Id = c.Id
JOIN
MapEntries m
ON
t.MapEntryId = m.Id
),

CTE_Deserialized_Positions AS (
SELECT				
	AccountId													
	,CAST(JSON_VALUE(value, '$.Value') AS INT)		AS TreeNodeId
	,CASE
			WHEN JSON_VALUE(value, '$.Name') = 'TreeNodeDebitId' THEN 'Wn'
			WHEN JSON_VALUE(value, '$.Name') = 'TreeNodeCreditId' THEN 'Ma'
	END AS Strona											
	FROM CTE_CurrentMapEntriesByTenantWithData
		MapEntries CROSS APPLY OPENJSON (MapEntries.Data) AS jv
	WHERE JSON_VALUE(value, '$.ReportId') = 22 OR JSON_VALUE(value, '$.ReportId') = 27
),

CTE_CurrentTrialBalanceAmounts AS (
	SELECT t.CreateDate 
			,t.AccountId 
			,e.[Data]
	FROM CTE_CurrentMapEntriesByTenant AS a
	JOIN TrialBalanceAmounts AS t ON a.AccountId = t.AccountId AND t.CreateDate = @CreateDate
	JOIN EnovaAmounts AS e ON e.Id = t.EnovaAmountId
),

/* Zestawienie Obrotów i Sald, tabela */
CTE_DeserializedAmounts AS (
	SELECT	AccountId
			,[ObrotyWn] ,[ObrotyMa] ,[SaldoWn] AS [Wn] ,[SaldoMa] AS [Ma]
	FROM CTE_CurrentTrialBalanceAmounts
	CROSS APPLY OPENJSON([Data])
		WITH (
			ObrotyWn decimal(12,2)
			,ObrotyMa decimal(12,2)
			,SaldoWn decimal(12,2)
			,SaldoMa decimal(12,2)
			)
),

CTE_UnpivotedAmounts AS (
	SELECT AccountId ,Strona ,Saldo  
	FROM (
			SELECT * 
			FROM CTE_DeserializedAmounts
		 ) AS cp
	UNPIVOT
		(
			Saldo FOR Strona IN (Wn, Ma)
		) AS up
	WHERE Saldo <> 0
),

CTE_Summed_TreeNodeId AS (
	SELECT p.AccountId, p.TreeNodeId ,SUM(-a.Saldo) AS Saldo
	FROM CTE_Deserialized_Positions AS p
	JOIN CTE_UnpivotedAmounts AS a on a.AccountId = p.AccountId AND p.Strona = a.Strona
	GROUP BY p.AccountId, p.TreeNodeId
),
--SELECT [Symbol] ,[Description] ,[SaldoCount] INTO #TCPositions
--		FROM udf_GetPLPositions_v06(@TenantId, @CreateDate)
CTE_PositionsWithAmounts AS (
	SELECT  tn.Id
			,p.AccountId
			,tn.[Description]
			,tn.IsNegative
			,tn.ReportNode
			,p.Saldo
	FROM CTE_Summed_TreeNodeId as p
	JOIN TreeNodes AS tn on tn.Id = p.TreeNodeId
)

SELECT
	Id,
	AccountId,
	Description,
	IsNegative,
	ReportNode,
	Saldo
	INTO #TCPositions
FROM CTE_PositionsWithAmounts

;With CTE_PositionsWithAccounts AS (
	SELECT  p.Id
			,p.AccountId
			,acc.Symbol
			,acc.Name
			,p.[Description]
			,p.IsNegative
			,p.ReportNode
			,p.Saldo
	FROM #TCPositions as p
	JOIN Accounts AS acc on acc.Id = p.AccountId
),

CTE_AggregatedPositionsWithAccounts AS (
	SELECT  Id
			,'' AS AccountId
			,'' AS Symbol
			,'' AS Name
			,[Description]
			,IsNegative
			,ReportNode
			,SUM(Saldo) AS Saldo
	FROM CTE_PositionsWithAccounts
	GROUP BY Id, IsNegative, [Description], ReportNode
),

CTE_PositionWithAccountsMerge AS (
	SELECT * FROM CTE_AggregatedPositionsWithAccounts
	UNION ALL
	SELECT * FROM CTE_PositionsWithAccounts
),

CTE_Report AS (
	SELECT  TreeNodes.[Id]
			,[ReportId]
			,[Node]
			,[Node].ToString() AS [NodeToString]
			,[Node].GetAncestor(1).ToString() AS [Ancestor]
			,[Description]
			,[IsNegative]
			,[ReportNode]
	 FROM TreeNodes
		WHERE (ReportId = 22 OR ReportId = 27)
		AND TreeNodes.Id NOT IN (202)																									/* Pozabilansowe, usuń mapping */
),

/* @ReportId plus wartości CTE_R_NodePlusValuesGroupByTreeNodeId */
CTE_ReportWithValuesToSum AS (																							
	SELECT  r.[Id]
			,r.[Node]
			,r.[ReportId]
			,r.[Description]
			,v.[Symbol]
			,v.[Name]
			,r.[IsNegative]
			,r.[ReportNode]
			,r.[ReportNode].ToString() AS ReportNodeString
			,ISNULL(v.Saldo ,0) AS [Saldo]
	FROM CTE_Report AS r
	LEFT JOIN CTE_PositionWithAccountsMerge AS v 
		ON v.Id = r.Id
),

CTE_Calculate AS (
	SELECT  
		p.[Id]
--			,p.[ReportId]
			,p.[Node]
			,p.[Node].GetAncestor(1) AS Ancestor
			,p.[ReportNode]
			,p.[Description]
			,p.[Symbol]
			,p.[Name]
			,p.[IsNegative]
			,CASE
				WHEN SUM(p.Saldo) = 0 THEN SUM(c.[Saldo]) / 2
				ELSE SUM(p.Saldo)
			END AS [SaldoCount]
	FROM CTE_ReportWithValuesToSum AS p
	LEFT JOIN CTE_ReportWithValuesToSum AS c
		ON p.[Node].GetAncestor(1) = 0x AND c.[ReportNode].IsDescendantOf(p.[ReportNode]) = 1
	WHERE p.[Id] <> 1
	GROUP BY p.[Id]
--			,p.[ReportId]
			,p.[Node]
			,p.[ReportNode]
			,p.[Description]
			,p.[Symbol]
			,p.[Name]
			,p.[IsNegative]
),

CTE_AddId AS (
	SELECT Id
	,Node
	,Ancestor
	,ReportNode
	,Description
	,Symbol
	,Name
	,IsNegative
	,SaldoCount
	,CASE
		WHEN Description = 'LIMIT | Thin cap' THEN 1
		WHEN Description = 'Koszty finansowania dłużnego' AND Id = 336 THEN 2
		WHEN Description = 'Odsetki  zapłacone' AND (Symbol = '' OR Symbol IS NULL) THEN 3
		WHEN Description = 'Odsetki  zapłacone' AND Symbol <> '' THEN 4
		WHEN Description = 'Odsetki uznane za zapłacone (w tym skapitalizowane)' AND (Symbol = '' OR Symbol IS NULL) THEN 5
		WHEN Description = 'Odsetki uznane za zapłacone (w tym skapitalizowane)' AND Symbol <> '' THEN 6
		WHEN Description = 'Odsetki ujęte w wartości ŚT lub WNiP - odsetkowa część odpisu amortyzacyjnego' AND (Symbol = '' OR Symbol IS NULL) THEN 7
		WHEN Description = 'Odsetki ujęte w wartości ŚT lub WNiP - odsetkowa część odpisu amortyzacyjnego' AND Symbol <> '' THEN 8
		WHEN Description = 'Opłaty' AND (Symbol = '' OR Symbol IS NULL) THEN 9
		WHEN Description = 'Opłaty' AND Symbol <> '' THEN 10
		WHEN Description = 'Prowizje' AND (Symbol = '' OR Symbol IS NULL) THEN 11
		WHEN Description = 'Prowizje' AND Symbol <> '' THEN 12
		WHEN Description = 'Premie' AND (Symbol = '' OR Symbol IS NULL) THEN 13
		WHEN Description = 'Premie' AND Symbol <> '' THEN 14
		WHEN Description = 'Inne koszty związane z finansowaniem' AND (Symbol = '' OR Symbol IS NULL) THEN 15
		WHEN Description = 'Inne koszty związane z finansowaniem' AND Symbol <> '' THEN 16
		WHEN Description = 'Część odsetkowa raty leasingowej' AND (Symbol = '' OR Symbol IS NULL) THEN 17
		WHEN Description = 'Część odsetkowa raty leasingowej' AND Symbol <> '' THEN 18
		WHEN Description = 'Kary i opłaty za opóźnienie w spłacie zobowiązań' AND (Symbol = '' OR Symbol IS NULL) THEN 19
		WHEN Description = 'Kary i opłaty za opóźnienie w spłacie zobowiązań' AND Symbol <> '' THEN 20
		WHEN Description = 'Koszty zabezpieczenia zobowiązań' AND (Symbol = '' OR Symbol IS NULL) THEN 21
		WHEN Description = 'Koszty zabezpieczenia zobowiązań' AND Symbol <> '' THEN 22
		WHEN Description = 'Różnice kursowe od odsetek zapłaconych i uznanych za zapłacone' AND (Symbol = '' OR Symbol IS NULL) THEN 23
		WHEN Description = 'Różnice kursowe od odsetek zapłaconych i uznanych za zapłacone' AND Symbol <> '' THEN 24
		WHEN Description = 'Przychody finansowania dłużnego' AND (Symbol = '' OR Symbol IS NULL) THEN 25
		WHEN Description = 'Przychody finansowania dłużnego' AND Symbol <> '' THEN 26
		WHEN Description = 'Odsetki  otrzymane' AND (Symbol = '' OR Symbol IS NULL) THEN 27
		WHEN Description = 'Odsetki  otrzymane' AND Symbol <> '' THEN 28
		WHEN Description = 'Odsetki uznane za otrzymane (również skapitalizowane)' AND (Symbol = '' OR Symbol IS NULL) THEN 29
		WHEN Description = 'Odsetki uznane za otrzymane (również skapitalizowane)' AND Symbol <> '' THEN 30
		WHEN Description = 'Inne przychody równoważne ekonomicznie odsetkom odpowiadające kosztom finansowania dłużnego' AND (Symbol = '' OR Symbol IS NULL) THEN 31
		WHEN Description = 'Inne przychody równoważne ekonomicznie odsetkom odpowiadające kosztom finansowania dłużnego' AND Symbol <> '' THEN 32
		WHEN Description = 'Różnice kursowe od odsetek otrzymanych i uznanych za otrzymane' AND (Symbol = '' OR Symbol IS NULL) THEN 33
		WHEN Description = 'Różnice kursowe od odsetek otrzymanych i uznanych za otrzymane' AND Symbol <> '' THEN 34
		WHEN Description = 'Nadwyżka kosztów finansowania dłużnego' AND (Symbol = '' OR Symbol IS NULL) THEN 35
		WHEN Description = 'Nadwyżka kosztów finansowania dłużnego' AND Symbol <> '' THEN 36
		WHEN Description = 'EBITDA' THEN 37
		WHEN Description = 'Przychody podatkowe' THEN 38
		WHEN Description = 'Odsetkowe przychody podatkowe' AND (Symbol = '' OR Symbol IS NULL) THEN 39
		WHEN Description = 'Odsetkowe przychody podatkowe' AND Symbol <> '' THEN 40
		WHEN Description = 'Koszty podatkowe' THEN 41
		WHEN Description = 'Amortyzacja' AND (Symbol = '' OR Symbol IS NULL) THEN 42
		WHEN Description = 'Amortyzacja' AND Symbol <> '' THEN 43
		WHEN Description = 'Koszty finansowania dłużnego ' AND (Symbol = '' OR Symbol IS NULL) THEN 44
		WHEN Description = 'Koszty finansowania dłużnego ' AND Symbol <> '' THEN 45
	END AS PositionId
	FROM CTE_Calculate
),

CTE_ThinCap AS (
	SELECT 
--			CTE_AddId.[Id]
			CTE_AddId.[Node]
--			,CTE_AddId.[ReportId]
			,CASE
				WHEN PositionId > 2 AND PositionId < 37 AND PositionId % 2 = 0 THEN ''
				WHEN PositionId = 43 OR PositionId = 45 THEN ''
				ELSE CTE_AddId.Description
			END AS [Description]
			,ISNULL(CTE_AddId.[Symbol], '') AS [Symbol]
			,ISNULL(CTE_AddId.[Name], '') AS [Name]
			,ISNULL(CASE
				WHEN CTE_AddId.IsNegative = 1 THEN -SaldoCount
				ELSE SaldoCount
			END ,0) AS [SaldoCount]
			,PositionId
	 FROM CTE_AddId
)

--SELECT * FROM CTE_TenantAccounts
--SELECT * FROM CTE_MapEntriesByDate
--SELECT * FROM CTE_CurrentMapEntriesByTenant order by Symbol
--SELECT * FROM CTE_CurrentMapEntriesByTenantWithData /* mapowania */
--SELECT * FROM CTE_Deserialized_Positions

--SELECT * FROM CTE_CurrentTrialBalanceAmounts
--SELECT * FROM CTE_DeserializedAmounts
--SELECT * FROM CTE_UnpivotedAmounts order by AccountId/* wartości */

--SELECT * FROM CTE_PositionsWithAccounts
--SELECT * FROM CTE_AggregatedPositionsWithAccounts
--SELECT * FROM CTE_PositionWithAccountsMerge

--SELECT * FROM CTE_Report
--SELECT * FROM CTE_ReportWithValuesToSum
--SELECT * FROM CTE_Calculate ORDER BY Node, Name
--SELECT * FROM CTE_AddId ORDER BY PositionId
--SELECT * FROM CTE_ThinCap ORDER BY PositionId

/* c# query end */

 SELECT 
 	DISTINCT 22 AS [ReportId]
 	,(	SELECT [PositionId] AS [Id],[Description], [SaldoCount] AS [Value], [Symbol] AS [Account], [Name]
 		FROM CTE_ThinCap
 		--WHERE Ancestor = '/'
 		ORDER BY Node, Name
 		FOR JSON PATH
 	 ) AS [Data]
 FROM CTE_ThinCap
END
GO