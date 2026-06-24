// Onboarding controller — holds the 6-step wizard's state in a single
// Notifier. The form is linear (no skipping per spec) so we model it as
// a stack index + accumulated values.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TreatmentStatus { activeTreatment, surveillance, remission, palliative }

TreatmentStatus? treatmentStatusFromString(String? s) {
  if (s == null) return null;
  switch (s) {
    case 'active_treatment':
      return TreatmentStatus.activeTreatment;
    case 'surveillance':
      return TreatmentStatus.surveillance;
    case 'remission':
      return TreatmentStatus.remission;
    case 'palliative':
      return TreatmentStatus.palliative;
  }
  return null;
}

String? treatmentStatusToString(TreatmentStatus? s) {
  if (s == null) return null;
  switch (s) {
    case TreatmentStatus.activeTreatment:
      return 'active_treatment';
    case TreatmentStatus.surveillance:
      return 'surveillance';
    case TreatmentStatus.remission:
      return 'remission';
    case TreatmentStatus.palliative:
      return 'palliative';
  }
}

@immutable
class OnboardingState {
  const OnboardingState({
    this.step = 0,
    this.fullName = '',
    this.primaryConditionId,
    this.primaryConditionLabel = '',
    this.conditionCategory,
    this.diagnosisDate,
    this.cancerStage = '',
    this.treatmentStatus,
    this.regimenName = '',
    this.dateOfBirth,
    this.sexAtBirth = '',
    this.connectHealthEnabled = true,
    this.consentAccepted = false,
  });

  final int step;
  final String fullName;
  final String? primaryConditionId;
  final String primaryConditionLabel;
  final String? conditionCategory;
  final DateTime? diagnosisDate;
  final String cancerStage;
  final TreatmentStatus? treatmentStatus;
  final String regimenName;
  final DateTime? dateOfBirth;
  final String sexAtBirth;
  final bool connectHealthEnabled;
  final bool consentAccepted;

  static const totalSteps = 6;

  OnboardingState copyWith({
    int? step,
    String? fullName,
    String? primaryConditionId,
    String? primaryConditionLabel,
    String? conditionCategory,
    DateTime? diagnosisDate,
    String? cancerStage,
    TreatmentStatus? treatmentStatus,
    String? regimenName,
    DateTime? dateOfBirth,
    String? sexAtBirth,
    bool? connectHealthEnabled,
    bool? consentAccepted,
    bool clearDiagnosisDate = false,
    bool clearDob = false,
    bool clearTreatmentStatus = false,
  }) => OnboardingState(
    step: step ?? this.step,
    fullName: fullName ?? this.fullName,
    primaryConditionId: primaryConditionId ?? this.primaryConditionId,
    primaryConditionLabel: primaryConditionLabel ?? this.primaryConditionLabel,
    conditionCategory: conditionCategory ?? this.conditionCategory,
    diagnosisDate: clearDiagnosisDate
        ? null
        : (diagnosisDate ?? this.diagnosisDate),
    cancerStage: cancerStage ?? this.cancerStage,
    treatmentStatus: clearTreatmentStatus
        ? null
        : (treatmentStatus ?? this.treatmentStatus),
    regimenName: regimenName ?? this.regimenName,
    dateOfBirth: clearDob ? null : (dateOfBirth ?? this.dateOfBirth),
    sexAtBirth: sexAtBirth ?? this.sexAtBirth,
    connectHealthEnabled: connectHealthEnabled ?? this.connectHealthEnabled,
    consentAccepted: consentAccepted ?? this.consentAccepted,
  );

  bool get isStep0Valid => fullName.trim().isNotEmpty;
  bool get isStep1Valid => primaryConditionId != null;
  bool get isStep2Valid {
    if (diagnosisDate == null || treatmentStatus == null) return false;
    if (conditionCategory == 'oncology' && cancerStage.trim().isEmpty)
      return false;
    return true;
  }

  bool get isStep3Valid => dateOfBirth != null && sexAtBirth.isNotEmpty;
  // step 4: HealthKit priming — always valid (informational)
  bool get isStep4Valid => true;
  // step 5 requires consent
  bool get isStep5Valid => consentAccepted;

  bool get isStepValid {
    switch (step) {
      case 0:
        return isStep0Valid;
      case 1:
        return isStep1Valid;
      case 2:
        return isStep2Valid;
      case 3:
        return isStep3Valid;
      case 4:
        return isStep4Valid;
      case 5:
        return isStep5Valid;
    }
    return false;
  }
}

class OnboardingController extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => const OnboardingState();

  void setStep(int step) {
    state = state.copyWith(step: step.clamp(0, OnboardingState.totalSteps - 1));
  }

  void next() {
    if (state.step < OnboardingState.totalSteps - 1) {
      state = state.copyWith(step: state.step + 1);
    }
  }

  void back() {
    if (state.step > 0) state = state.copyWith(step: state.step - 1);
  }

  void setName(String v) => state = state.copyWith(fullName: v);
  void setCondition({
    required String id,
    required String label,
    String? category,
  }) => state = state.copyWith(
    primaryConditionId: id,
    primaryConditionLabel: label,
    conditionCategory: category,
  );
  void setDiagnosisDate(DateTime? d) =>
      state = state.copyWith(diagnosisDate: d, clearDiagnosisDate: d == null);
  void setCancerStage(String v) => state = state.copyWith(cancerStage: v);
  void setTreatmentStatus(TreatmentStatus? s) => state = state.copyWith(
    treatmentStatus: s,
    clearTreatmentStatus: s == null,
  );
  void setRegimenName(String v) => state = state.copyWith(regimenName: v);
  void setDateOfBirth(DateTime? d) =>
      state = state.copyWith(dateOfBirth: d, clearDob: d == null);
  void setSexAtBirth(String v) => state = state.copyWith(sexAtBirth: v);
  void setConnectHealthEnabled(bool v) =>
      state = state.copyWith(connectHealthEnabled: v);
  void setConsentAccepted(bool v) => state = state.copyWith(consentAccepted: v);
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );
