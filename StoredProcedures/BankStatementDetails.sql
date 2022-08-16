CREATE PROCEDURE [dbo].[BankStatementDetails]
AS
BEGIN

WITH CTE_DimensionsControlling AS (
	SELECT [BankStatementDetailId]
      ,[CostAccountId]
      ,[DeferredAccountId]
      ,[ExpenseDate]
      ,[PositionAmount]
  FROM [dbo].[DimensionsControlling]
)

,CTE_DimensionsControllingSum AS (
	SELECT BankStatementDetailId,
	SUM(PositionAmount) AS DocumentAmount
	FROM CTE_DimensionsControlling
	GROUP BY BankStatementDetailId
)

,CTE_DimensionsControllingMerge AS (
	SELECT CTE_DimensionsControlling.[BankStatementDetailId]
      ,[CostAccountId]
      ,[DeferredAccountId]
      ,[ExpenseDate]
      ,[PositionAmount]
	  ,[DocumentAmount]
      ,([PositionAmount]/[DocumentAmount]) AS [Percentage]
	FROM CTE_DimensionsControlling
	LEFT JOIN CTE_DimensionsControllingSum
	ON CTE_DimensionsControlling.BankStatementDetailId = CTE_DimensionsControllingSum.BankStatementDetailId
)

,CTE_DimensionsAccountant AS (
	SELECT [DimensionAccountantId]
      ,[BankStatementDetailId]
      ,[VatRateId]
      --,[VatAmount]
      ,[CreditorId]
      ,[PostingDescription]
      ,[DocumentNumber]
      ,[VatDate]
      ,[InvoiceIssueDate]
      ,[AmountInOriginalCurrency]
      ,[OriginalCurrency]
      ,[AmountInPln]
      ,[ExchangeRate]
  FROM [dbo].[DimensionsAccountant]
)

,CTE_DimensionKeyAccount AS (
	SELECT [EnovaId]
      ,[ExpenditureTypeId]
      ,[CostTypeId]
      ,[CostCenterId]
      ,[ProjectId]
      ,[CustomerId]
      ,[CountryId]
      ,[NumberOfPeople]
      ,[VehicleTypeId]
      ,[VehicleId]
      ,[VehiclePlateNumber]
      ,[ProjectName]
      ,[Comment]
      ,[IsReinvoiced]
      ,[NumberOfDocument]
  FROM [dbo].[DimensionsKeyAccount]
)

,CTE_BankStatementDetails AS (
	SELECT [BankStatementDetailId]
      ,[EnovaId]
      ,[PaymentDate]
      ,[Description]
      ,[AccountNumber]
      ,[Amount]
      ,[Currency]
	  ,[OriginalCurrencyAmount]
      ,[OriginalCurrency]
      ,[Status]
  FROM [dbo].[BankStatementDetails]
)

,CTE_BankStatementDetailsMerge AS (
	SELECT
		BSD.BankStatementDetailId,
		BSD.PaymentDate as DataWplywu, -- as DataEwidencji, as PlatnosciTermin
		CASE
			WHEN LEN(BSD.[Description]) > 60 THEN LEFT(BSD.[Description], 60)
			ELSE BSD.[Description]
		END as PlatnosciOpis,
		BSD.AccountNumber AS PracownikId,-- IdPracownik np. P0122
		--BSD.Amount,
		--BSD.Currency,
		DKA.NumberOfPeople as OpisAnalitycznyFeaturesLiczbaosob,
		CASE
			WHEN DKA.VehiclePlateNumber IS NOT NULL THEN DKA.VehiclePlateNumber
			ELSE VEH.PlateNumber
		END as OpisAnalitycznyFeaturesSamochodNrRej,
		VT.Name as OpisAnalitycznyFeaturesSamochodTyp,
		DKA.Comment as OpisAnalitycznyFeaturesDescription,
		ISNULL(DKA.IsReinvoiced, 0) as OpisAnalitycznyFeaturesRefaktura,
		--DC.PositionAmount,
		--DC.Percentage,
		--DA.AmountInPln,
		CASE
			WHEN DA.AmountInOriginalCurrency IS NOT NULL THEN CONVERT(decimal(18,2), ROUND(DA.AmountInOriginalCurrency * ISNULL(DC.Percentage, 1), 2))
			ELSE CONVERT(decimal(18,2), ROUND(BSD.OriginalCurrencyAmount * ISNULL(DC.Percentage, 1), 2))
		END AS PlatnosciKwotaAmount,
		CASE
			WHEN DA.AmountInOriginalCurrency IS NOT NULL THEN DA.OriginalCurrency
			ELSE BSD.OriginalCurrency
		END AS PlatnosciKwotaWaluta,
		DA.ExchangeRate AS PlatnosciKurs,
		CASE
			WHEN ISNULL(DA.OriginalCurrency, BSD.OriginalCurrency) <> 'PLN' AND DA.AmountInPln IS NOT NULL THEN CONVERT(decimal(18,2), ROUND(DA.AmountInPln * ISNULL(DC.Percentage, 1), 2))
			WHEN ISNULL(DA.OriginalCurrency, BSD.OriginalCurrency) <> 'PLN' AND BSD.Amount IS NOT NULL THEN CONVERT(decimal(18,2), ROUND(BSD.Amount * ISNULL(DC.Percentage, 1), 2))
			ELSE CONVERT(decimal(18,2), ROUND(ISNULL(DA.AmountInOriginalCurrency, BSD.OriginalCurrencyAmount) * ISNULL(DC.Percentage, 1), 2))
		END as PlatnosciKwotaKsiegi, --AS KwotaBruttoPozycjiPLN,
		DC.ExpenseDate as DefferedAccountDate,
		--DA.CreditorId,
		CR.Number as PodmiotKod,
		CASE
			WHEN DA.PostingDescription <> '' AND DA.PostingDescription IS NOT NULL THEN DA.PostingDescription
			WHEN DKA.Comment <> '' AND DKA.Comment IS NOT NULL THEN DKA.Comment
			ELSE CASE
				WHEN LEN(BSD.[Description]) > 60 THEN LEFT(BSD.[Description], 60)
				ELSE BSD.[Description]
				END
		END as Opis, -- as OpisAnalitycznyOpis
		CASE
			WHEN DA.DocumentNumber <> '' AND DA.DocumentNumber IS NOT NULL THEN DA.DocumentNumber
			ELSE DKA.NumberOfDocument
		END as NumerDokumentu,
		CASE
			WHEN DA.VatDate IS NOT NULL THEN DA.VatDate
			ELSE PaymentDate
		END as WorkersEwidencjaVATNagEwidencjiVATDataZaewidencjonowania,
		DA.InvoiceIssueDate AS DataDokumentu, -- as DataEwidencji
		CA.Number as CostAccount,
		--CA.Name AS AccName,
		DAC.Number as DeferredAccount,
		--DAC.Name AS RmkName,
		CC.EnovaId as OpisAnalitycznyFeaturesMPKID,
		--CC.Name AS CostCenterName,
		--CT.CostTypeId,
		--CT.Name AS CostTypeName,
		CTR.EnovaId  as OpisAnalitycznyFeaturesKrajID,
		--CTR.Name AS CountryName,
		ET.Name as TypWydatku,
		PR.ProjectId AS ProjectId,
		DKA.ProjectName as OpisAnalitycznyFeaturesProject,
		--CU.Name AS CustomerName,
		CU.EnovaId as OpisAnalitycznyFeaturesKlientID,
		--DKA.CustomerId AS CustomerId,
		--VR.VatRateId AS TaxId,
		VR.Rate as NagEwidencjiVATElementyDefinicjaStawkiKod,
		CASE
			WHEN DA.OriginalCurrency IS NOT NULL THEN DA.OriginalCurrency
			ELSE BSD.OriginalCurrency
		END AS OriginalCurrency,
		DC.PositionAmount,
		DC.DocumentAmount,
		DA.AmountInPln,
		BSD.Amount,
		DC.Percentage,
		CASE
			WHEN VR.Rate = '23%'
				THEN CONVERT(decimal(18,2), ROUND(ROUND(ISNULL(DA.AmountInPln, ISNULL(DC.DocumentAmount, BSD.Amount)) * ISNULL(DC.Percentage, 1), 2) * 0.23 / (1 + 0.23), 2))
			WHEN VR.Rate = '8%'
				THEN CONVERT(decimal(18,2), ROUND(ROUND(ISNULL(DA.AmountInPln, ISNULL(DC.DocumentAmount, BSD.Amount)) * ISNULL(DC.Percentage, 1), 2) * 0.08 / (1 + 0.08), 2))
			WHEN VR.Rate = '5%'
				THEN CONVERT(decimal(18,2), ROUND(ROUND(ISNULL(DA.AmountInPln, ISNULL(DC.DocumentAmount, BSD.Amount)) * ISNULL(DC.Percentage, 1), 2) * 0.05 / (1 + 0.05), 2))
			ELSE 0
		END AS NagEwidencjiVATElementyVAT,
		DA.VatRateId
		FROM CTE_BankStatementDetails BSD
		LEFT JOIN CTE_DimensionKeyAccount DKA On BSD.EnovaId = DKA.EnovaId
		LEFT JOIN CTE_DimensionsControllingMerge DC On BSD.BankStatementDetailId = DC.BankStatementDetailId
		LEFT JOIN CTE_DimensionsAccountant DA ON BSD.BankStatementDetailId = DA.BankStatementDetailId
		LEFT JOIN CostAccounts CA ON DC.CostAccountId = CA.CostAccountId
		LEFT JOIN CostCenters CC ON DKA.CostCenterId = CC.CostCenterId
		LEFT JOIN CostTypes CT ON DKA.CostTypeId = CT.CostTypeId
		LEFT JOIN Countries CTR ON DKA.CountryId = CTR.CountryId
		LEFT JOIN DeferredAccounts DAC ON DC.DeferredAccountId = DAC.DeferredAccountId
		LEFT JOIN ExpenditureTypes ET ON DKA.ExpenditureTypeId = ET.ExpenditureTypeId
		LEFT JOIN Projects PR ON DKA.ProjectId = PR.ProjectId
		LEFT JOIN Customers CU ON DKA.CustomerId = CU.CustomerId
		LEFT JOIN VatRates VR ON DA.VatRateId = VR.VatRateId
		LEFT JOIN Vehicles VEH ON DKA.VehicleId = VEH.VehicleId
		LEFT JOIN VehicleTypes VT ON DKA.VehicleTypeId = VT.VehicleTypeId
		LEFT JOIN Creditors CR ON DA.CreditorId = CR.CreditorId
)

,CTE_GetDefferedLinesFirstPosting AS (
	SELECT
	BankStatementDetailId,
	CASE
		WHEN DataDokumentu IS NOT NULL THEN DataDokumentu
		ELSE DataWplywu
	END AS DataDokumentu, -- as DataOperacji
	DataWplywu, -- as DataEwidencji, as PlatnosciTermin
	PlatnosciOpis,
	PlatnosciKwotaAmount,
	PlatnosciKwotaWaluta,
	PlatnosciKwotaKsiegi,
	CASE
		WHEN PlatnosciKurs IS NOT NULL THEN PlatnosciKurs
		ELSE ABS(CONVERT(decimal(18,4), ROUND(PlatnosciKwotaKsiegi / PlatnosciKwotaAmount, 4)))
	END AS PlatnosciKurs,
	OpisAnalitycznyFeaturesLiczbaosob,
	OpisAnalitycznyFeaturesSamochodNrRej,
	OpisAnalitycznyFeaturesSamochodTyp,
	OpisAnalitycznyFeaturesDescription,
	OpisAnalitycznyFeaturesRefaktura,
	PodmiotKod,
	CASE
		WHEN Opis IS NULL THEN OpisAnalitycznyFeaturesDescription
		ELSE Opis
	END AS Opis,
	NumerDokumentu,
	DeferredAccount as OpisAnalitycznySymbol,
	DataWplywu as DataEwidencji,
	OpisAnalitycznyFeaturesMPKID,
	OpisAnalitycznyFeaturesKrajID,
	OpisAnalitycznyFeaturesProject,
	OpisAnalitycznyFeaturesKlientID,
	NagEwidencjiVATElementyDefinicjaStawkiKod,
	NagEwidencjiVATElementyVAT,
	PlatnosciKwotaKsiegi - NagEwidencjiVATElementyVAT AS NagEwidencjiVATElementyNetto,
	PlatnosciKwotaKsiegi - NagEwidencjiVATElementyVAT AS OpisAnalitycznyKwota,
	WorkersEwidencjaVATNagEwidencjiVATDataZaewidencjonowania,
	PracownikId,
	TypWydatku,
	1 as Kolejnosc
	FROM CTE_BankStatementDetailsMerge
	WHERE DeferredAccount IS NOT NULL
)

,CTE_GetCostLinesFirstPosting AS (
	SELECT
	BankStatementDetailId,
	CASE
		WHEN DataDokumentu IS NOT NULL THEN DataDokumentu
		ELSE DataWplywu
	END AS DataDokumentu, -- as DataOperacji
	DataWplywu, -- as DataEwidencji, as PlatnosciTermin
	PlatnosciOpis, 
	PlatnosciKwotaAmount,
	PlatnosciKwotaWaluta,
	PlatnosciKwotaKsiegi,
	CASE
		WHEN PlatnosciKurs IS NOT NULL THEN PlatnosciKurs
		ELSE ABS(CONVERT(decimal(18,4), PlatnosciKwotaKsiegi / PlatnosciKwotaAmount))
	END AS PlatnosciKurs,
	OpisAnalitycznyFeaturesLiczbaosob,
	OpisAnalitycznyFeaturesSamochodNrRej,
	OpisAnalitycznyFeaturesSamochodTyp,
	OpisAnalitycznyFeaturesDescription,
	OpisAnalitycznyFeaturesRefaktura,
	PodmiotKod,
	CASE
		WHEN Opis IS NULL THEN OpisAnalitycznyFeaturesDescription
		ELSE Opis
	END AS Opis,
	NumerDokumentu,
	CostAccount as OpisAnalitycznySymbol,
	DataWplywu AS DataEwidencji,
	OpisAnalitycznyFeaturesMPKID,
	OpisAnalitycznyFeaturesKrajID,
	OpisAnalitycznyFeaturesProject,
	OpisAnalitycznyFeaturesKlientID,
	NagEwidencjiVATElementyDefinicjaStawkiKod,
	NagEwidencjiVATElementyVAT,
	PlatnosciKwotaKsiegi - NagEwidencjiVATElementyVAT AS NagEwidencjiVATElementyNetto,
	PlatnosciKwotaKsiegi - NagEwidencjiVATElementyVAT AS OpisAnalitycznyKwota,
	WorkersEwidencjaVATNagEwidencjiVATDataZaewidencjonowania,
	PracownikId,
	TypWydatku,
	1 as Kolejnosc
	FROM CTE_BankStatementDetailsMerge
	WHERE DeferredAccount IS NULL OR TypWydatku = 'prywatne'
)

,CTE_MergePostings AS (
	SELECT * FROM CTE_GetDefferedLinesFirstPosting
	UNION ALL
	SELECT * FROM CTE_GetCostLinesFirstPosting
)

,CTE_PrepareUpload AS (
	SELECT
	'ZakupEwidencja' as Class,
	NumerDokumentu,
	CASE
		WHEN Kolejnosc = 1 THEN CONCAT(LEFT(NumerDokumentu,26), ' ', BankStatementDetailId)
		ELSE CONCAT(LEFT(NumerDokumentu,26), ' ', BankStatementDetailId, '/RMK')
	END as NumerDodatkowy,
	DataDokumentu,
	DataEwidencji,
	DataWplywu,
	DataDokumentu as DataOperacji,
	CASE
		WHEN TypWydatku = 'prywatny' THEN NULL 
		WHEN NagEwidencjiVATElementyDefinicjaStawkiKod IS NULL THEN NULL
		ELSE WorkersEwidencjaVATNagEwidencjiVATDataZaewidencjonowania
	END AS WorkersEwidencjaVATNagEwidencjiVATDataZaewidencjonowania,
	CASE
		WHEN PodmiotKod IS NULL THEN 'Pracownik'
		ELSE CASE
			WHEN Kolejnosc = 1 THEN
			CASE
				WHEN TypWydatku = 'sluzbowy' THEN 'Kontrahent'
				ELSE 'Pracownik'
				END
			ELSE 'Pracownik'
		END
	END as PodmiotClass,
	CASE
		WHEN PodmiotKod IS NULL THEN PracownikId
		ELSE CASE
			WHEN Kolejnosc = 1 THEN
			CASE
				WHEN TypWydatku = 'sluzbowy' THEN CONVERT(varchar, PodmiotKod)
				ELSE PracownikId
				END
			ELSE PracownikId
		END
	END as PodmiotKod,
	CASE
		WHEN Kolejnosc = 1 THEN
		CASE
			WHEN TypWydatku = 'sluzbowy' THEN PracownikID
			ELSE NULL
			END
		ELSE NULL
	END as FeaturesPracownik,
	LEFT(Opis,80) AS Opis,
	CASE
		WHEN PlatnosciOpis IS NOT NULL THEN
			CASE
				WHEN PlatnosciKwotaKsiegi > 0 THEN 'Zobowiazanie'
				ELSE 'Naleznosc'
			END
	END as PlatnosciClass,
	CASE
		WHEN PlatnosciOpis IS NOT NULL THEN 'Przelew'
	END as PlatnosciSposobZaplatyNazwa,
	CASE
		WHEN PlatnosciOpis IS NOT NULL THEN DataDokumentu
	END as PlatnosciTermin,
	CASE
		WHEN PlatnosciKwotaWaluta = 'PLN' THEN CONVERT(varchar, ABS(PlatnosciKwotaAmount))
		WHEN PlatnosciKwotaWaluta IS NULL THEN NULL
		ELSE CONCAT(REPLACE(CONVERT(varchar, ABS(PlatnosciKwotaAmount)),'.',','), PlatnosciKwotaWaluta)
	END as PlatnosciKwota,
	REPLACE(CONVERT(varchar, ABS(PlatnosciKwotaKsiegi)),'.',',') AS PlatnosciKwotaKsiegi,
	PlatnosciKurs,
	PlatnosciOpis,
	CASE
		WHEN TypWydatku = 'prywatny' THEN NULL 
		WHEN NagEwidencjiVATElementyDefinicjaStawkiKod IS NULL THEN NULL
		WHEN NagEwidencjiVATElementyNetto IS NOT NULL THEN 'ElemEwidencjiVATZakup'
	END as NagEwidencjiVATElementyClass,
	CASE
		WHEN TypWydatku = 'prywatny' THEN NULL
		WHEN NagEwidencjiVATElementyDefinicjaStawkiKod IS NULL THEN NULL
		ELSE NagEwidencjiVATElementyDefinicjaStawkiKod
	END AS NagEwidencjiVATElementyDefinicjaStawkiKod,
	CASE
		WHEN TypWydatku = 'prywatny' THEN NULL
		WHEN NagEwidencjiVATElementyDefinicjaStawkiKod IS NULL THEN NULL
		ELSE NagEwidencjiVATElementyNetto
	END AS NagEwidencjiVATElementyNetto,
	CASE
		WHEN TypWydatku = 'prywatny' THEN NULL
		WHEN NagEwidencjiVATElementyDefinicjaStawkiKod IS NULL THEN NULL
		ELSE NagEwidencjiVATElementyVAT
	END AS NagEwidencjiVATElementyVAT,
	CASE
		WHEN TypWydatku = 'prywatny' THEN NULL
		WHEN NagEwidencjiVATElementyDefinicjaStawkiKod IS NULL THEN NULL
		WHEN NagEwidencjiVATElementyNetto IS NOT NULL THEN 'Usługi'
	END as NagEwidencjiVATElementyRodzaj,
	CASE
		WHEN TypWydatku = 'prywatny' THEN NULL
		WHEN NagEwidencjiVATElementyDefinicjaStawkiKod IS NULL THEN NULL
		WHEN NagEwidencjiVATElementyNetto IS NOT NULL THEN 'Tak'
	END as NagEwidencjiVATElementyOdliczenia,
	'ElementOpisuEwidencji' as OpisAnalitycznyClass,
	CASE
		WHEN OpisAnalitycznyKwota > 0 THEN 'wn'
		ELSE 'ma'
	END AS OpisAnalitycznyWymiar,
	CASE
		WHEN TypWydatku = 'sluzbowy' THEN OpisAnalitycznySymbol
		ELSE '100-01'
	END AS OpisAnalitycznySymbol,
	ABS(CONVERT(decimal(18,2), OpisAnalitycznyKwota)) as OpisAnalitycznyKwota,
	ABS(CONVERT(decimal(18,2), OpisAnalitycznyKwota)) as OpisAnalitycznyKwotaDodatkowa,
	LEFT(Opis, 80) as OpisAnalitycznyOpis,
	OpisAnalitycznyFeaturesMPKID,
	OpisAnalitycznyFeaturesProject,
	OpisAnalitycznyFeaturesKrajID,
	OpisAnalitycznyFeaturesKlientID,
	OpisAnalitycznyFeaturesDescription,
	CASE
		WHEN OpisAnalitycznyFeaturesRefaktura = 0 THEN 'false'
		ELSE 'true'
	END AS OpisAnalitycznyFeaturesRefaktura,
	CASE
		WHEN OpisAnalitycznyFeaturesSamochodTyp = 'Brak wyboru' THEN NULL
		ELSE OpisAnalitycznyFeaturesSamochodTyp
	END AS OpisAnalitycznyFeaturesSamochodTyp,
	OpisAnalitycznyFeaturesSamochodNrRej,
	OpisAnalitycznyFeaturesLiczbaosob,
	BankStatementDetailId
	FROM CTE_MergePostings
)

,CTE_GetKey AS (
SELECT *
, CONCAT(NumerDokumentu, NumerDodatkowy, PodmiotKod, CONVERT(decimal(18,0),DataDokumentu)) AS Klucz
FROM CTE_PrepareUpload
)

SELECT * FROM
--CTE_DimensionsControlling
--CTE_DimensionsControllingSum
--CTE_DimensionsControllingMerge
--CTE_DimensionsAccountant
--CTE_DimensionKeyAccount
--CTE_BankStatementDetails
--CTE_BankStatementDetailsMerge
--CTE_GetDefferedLinesFirstPosting
--CTE_GetDefferedLinesSecondPosting
--CTE_GetCostLinesFirstPosting
--CTE_GetCostLinesSecondPosting
--CTE_MergePostings
--CTE_PrepareUpload
CTE_GetKey
ORDER BY BankStatementDetailId, DataDokumentu

END
GO