#!/usr/bin/env bash

runtime_requirement_is_team_bound() {
  if (( $# != 2 )); then
    return 1
  fi

  local requirement_details="$1"
  local development_team="$2"
  local normalized_requirement_details
  local structural_requirement_details=''
  local uncommented_requirement_details=''
  local normalized_requirement_details_lowercase
  local subject_ou_requirement='certificate leaf[subject.OU]'
  local requirement_after_subject_ou
  local unsafe_boolean_pattern
  local exact_team_requirement_pattern
  local quoted_value=''
  local character
  local character_pair
  local character_index
  local requirement_length
  local in_quoted_value=0
  local escaped_character=0
  local in_block_comment=0

  if [[ ! "$development_team" =~ ^[A-Z0-9]{10}$ ]]; then
    return 1
  fi

  normalized_requirement_details="$(
    printf '%s\n' "$requirement_details" | LC_ALL=C tr -s '[:space:]' ' '
  )" || return 1

  # Keep only requirement syntax outside string literals. Preserve the exact
  # expected team when it is the complete quoted value so that the predicate
  # matcher can accept codesign's quoted form. All other quoted content is
  # masked, preventing a predicate-shaped string value from being mistaken for
  # a real certificate constraint.
  requirement_length=${#normalized_requirement_details}
  for ((character_index = 0; character_index < requirement_length; character_index++)); do
    character="${normalized_requirement_details:character_index:1}"
    if ((in_quoted_value)); then
      if ((escaped_character)); then
        quoted_value+="$character"
        escaped_character=0
      elif [[ "$character" == \\ ]]; then
        escaped_character=1
      elif [[ "$character" == '"' ]]; then
        if [[ "$quoted_value" == "$development_team" ]]; then
          structural_requirement_details+="\"$development_team\""
        else
          structural_requirement_details+='""'
        fi
        quoted_value=''
        in_quoted_value=0
      else
        quoted_value+="$character"
      fi
    elif [[ "$character" == '"' ]]; then
      in_quoted_value=1
    else
      structural_requirement_details+="$character"
    fi
  done
  if ((in_quoted_value || escaped_character)); then
    return 1
  fi

  # codesign renders existence annotations as block comments. Exclude comment
  # contents as well, so predicate-shaped comment text cannot satisfy the OU
  # check. Nested or unterminated comments are rejected conservatively.
  requirement_length=${#structural_requirement_details}
  for ((character_index = 0; character_index < requirement_length; character_index++)); do
    character_pair="${structural_requirement_details:character_index:2}"
    if ((in_block_comment)); then
      if [[ "$character_pair" == '/*' ]]; then
        return 1
      fi
      if [[ "$character_pair" == '*/' ]]; then
        in_block_comment=0
        ((character_index += 1))
      fi
    elif [[ "$character_pair" == '/*' ]]; then
      in_block_comment=1
      ((character_index += 1))
    else
      uncommented_requirement_details+="${structural_requirement_details:character_index:1}"
    fi
  done
  if ((in_block_comment)); then
    return 1
  fi

  normalized_requirement_details="$(
    printf '%s\n' "$uncommented_requirement_details" | LC_ALL=C tr -s '[:space:]' ' '
  )" || return 1
  normalized_requirement_details_lowercase="$(
    printf '%s\n' "$normalized_requirement_details" | LC_ALL=C tr '[:upper:]' '[:lower:]'
  )" || return 1

  # A team clause inside a disjunction or negation is not proof that every
  # accepted signer belongs to that team. The canonical requirements emitted
  # by codesign for this path are conjunctive, so reject those operators rather
  # than trying to infer arbitrary requirement-grammar semantics here.
  unsafe_boolean_pattern='(^|[[:space:]]|\()(or|not)($|[[:space:]]|\))'
  if [[ "$normalized_requirement_details_lowercase" =~ $unsafe_boolean_pattern \
    || "$normalized_requirement_details" == *'!'* \
    || "$normalized_requirement_details" == *'|'* ]]; then
    return 1
  fi

  # Require exactly one leaf-OU predicate. This prevents a second OU condition
  # from changing the meaning of the exact expected predicate.
  if [[ "$normalized_requirement_details" != *"$subject_ou_requirement"* ]]; then
    return 1
  fi
  requirement_after_subject_ou="${normalized_requirement_details#*"$subject_ou_requirement"}"
  if [[ "$requirement_after_subject_ou" == *"$subject_ou_requirement"* ]]; then
    return 1
  fi

  exact_team_requirement_pattern="(^|[[:space:]]|\\()certificate[[:space:]]+leaf\\[subject\\.OU\\][[:space:]]*=[[:space:]]*(\"${development_team}\"|${development_team})($|[[:space:]]|\\))"
  [[ "$normalized_requirement_details" =~ $exact_team_requirement_pattern ]]
}
