/-
Axiom audit for the headline theorems (Rule 3 guardrail).

    export PATH="$HOME/.elan/bin:$PATH"
    lake env lean Audit.lean

One `#print axioms` line per theorem in headline-theorems.txt.
Allowed axioms: propext, Classical.choice, Quot.sound.
-/
import Specs

#print axioms Saga.ce1_confirm_after_cancel
#print axioms Saga.ce2_redelivery_duplicate
#print axioms Saga.ce3_book_failure_stuck
#print axioms Saga.ce4_cancel_failure_stuck
#print axioms Saga.ce5_flight_ref_mismatch
#print axioms Saga.stuck_is_permanent
#print axioms Saga.br3_always
#print axioms Saga.br4_of_no_redelivery
#print axioms Saga.br6_of_no_flight_bug
#print axioms Saga.br8_of_no_failures
#print axioms Saga.br2_of_reliable
#print axioms Saga.br5_of_reliable
#print axioms Saga.br7_of_reliable
#print axioms Saga.quint_matrix
#print axioms Saga.quint_allFaults_BR1
#print axioms Saga.quint_allFaults_BR2
#print axioms Saga.quint_allFaults_BR4
#print axioms Saga.quint_allFaults_BR5
#print axioms Saga.quint_allFaults_BR6
#print axioms Saga.quint_allFaults_BR7
#print axioms Saga.quint_allFaults_BR8
#print axioms Saga.quint_asIs_BR1
#print axioms Saga.quint_asIs_BR2
#print axioms Saga.quint_asIs_BR5
#print axioms Saga.quint_asIs_BR6
#print axioms Saga.quint_asIs_BR7
#print axioms Saga.quint_bookFailure_BR1
#print axioms Saga.quint_bookFailure_BR8
#print axioms Saga.quint_cancelFailure_BR1
#print axioms Saga.quint_cancelFailure_BR8
#print axioms Saga.quint_ideal_BR1
#print axioms Saga.quint_redelivery_BR1
#print axioms Saga.quint_redelivery_BR2
#print axioms Saga.quint_redelivery_BR4
#print axioms Saga.quint_redelivery_BR5
#print axioms Saga.quint_redelivery_BR7
