Require Import String.
Require Import RelationClasses.
Require Import List.
Require Import ListAdd.
Require Import Rbase Rtrigo Rpower Rbasic_fun.
Require Import DefinedFunctions.
Require Import Lra.

Require Import BasicTactics.
Require Import ListAdd Assoc.

Record FullNN : Type := mkNN { ldims : list nat; param_var : SubVar; 
                              f_activ : DefinedFunction ; f_loss : DefinedFunction }.

Definition mkRvector (lr : list R) : list DefinedFunction :=
    map (fun r => Number r) lr.

Definition mkSubVarVector (v : SubVar) (n : nat) : list DefinedFunction :=
    map (fun n => Var (Sub v n)) (seq 1 n).

Definition mkSubVarMatrix (v : SubVar) (n m : nat) : list (list DefinedFunction) :=
    map (fun n =>  mkSubVarVector (Sub v n) m) (seq 1 n).

Definition vecprod (vec1 vec2 : list DefinedFunction) : DefinedFunction :=
  fold_right (fun x y => Plus x y) (Number 0) (map (fun '(x,y) => Times x y) (combine vec1 vec2)).

Definition mul_mat_vec (mat : list (list DefinedFunction)) (vec : list DefinedFunction) : list DefinedFunction :=
  map (fun row => vecprod row vec) mat.

Definition unique_var (df : DefinedFunction) : option SubVar :=
  let fv := nodup var_dec (df_free_variables df) in
  match fv with
  | nil => None
  | v :: nil => Some v
  | _ => None
  end.   

Definition activation (df : DefinedFunction) (vec : list DefinedFunction) : option (list DefinedFunction) :=
    match unique_var df with
    | Some v => Some (map (fun dfj => df_subst df v dfj) vec)
    | None => None
    end.

Definition mkNN2 (n1 n2 n3 : nat) (ivar wvar : SubVar) (f_activ : DefinedFunction) : option (list DefinedFunction) :=
  let mat1 := mkSubVarMatrix (Sub wvar 1) n1 n2 in
  let mat2 := mkSubVarMatrix (Sub wvar 2) n2 n3 in
  let ivec := mkSubVarVector ivar n1 in
  let N1 := activation f_activ (mul_mat_vec mat1 ivec) in 
  match N1 with
  | Some vec => activation f_activ (mul_mat_vec mat2 vec)
  | None => None
  end.

Record testcases : Type := mkTest {ninput: nat; noutput: nat; ntest: nat; 
                                   data : list ((list R) * (list R))}.

Definition deltalosses (df : DefinedFunction) (losses : list DefinedFunction) : option DefinedFunction :=
  let losslist : option (list DefinedFunction) :=
      match unique_var df with
      | Some v => Some (map (fun dfj => df_subst df v dfj) losses)
      | None => None
      end 
  in
  match losslist with
  | Some l => Some (fold_right Plus (Number R0) l)
  | None => None
  end.

Lemma deltalosses_unique_var {df : DefinedFunction} {v:SubVar} :
  unique_var df = Some v ->
  forall  (losses : list DefinedFunction),
  deltalosses df losses = Some (fold_right Plus (Number R0) (map (fun dfj => df_subst df v dfj) losses)).
Proof.
  unfold deltalosses; intros eqq.
  rewrite eqq; reflexivity.
Qed.

Lemma deltalosses_None {df : DefinedFunction} :
  unique_var df = None ->
  forall (losses : list DefinedFunction),
  deltalosses df losses = None.
Proof.
  unfold deltalosses; intros eqq.
  rewrite eqq; reflexivity.
Qed.

Definition NNinstance (n1 n2 n3 : nat) (ivar : SubVar) (f_loss : DefinedFunction) 
           (NN2 : list DefinedFunction) (inputs : (list R)) 
           (outputs : (list R)): option DefinedFunction :=
  let ipairs := (list_prod (map (fun n => (Sub ivar n)) (seq 1 n1))
                           (map Number inputs)) in
  let inputFunctions := (map (fun df => df_subst_list df ipairs) NN2) in
  let losses := (map (fun '(df,outval) =>  (Minus df (Number outval)))
                     (list_prod inputFunctions outputs)) in
     deltalosses f_loss losses.


Lemma NNinstance_unique_var (n1 n2 n3 : nat) (ivar : SubVar) (f_loss : DefinedFunction) 
      (NN2 : list DefinedFunction) (inputs : (list R)) 
      (outputs : (list R)) (v:SubVar) :
  unique_var f_loss = Some v ->
  NNinstance n1 n2 n3 ivar f_loss NN2 inputs outputs =
  Some (
      let ipairs := (list_prod (map (fun n => (Sub ivar n)) (seq 1 n1))
                               (map Number inputs)) in
      let inputFunctions := (map (fun df => df_subst_list df ipairs) NN2) in
      let losses := (map (fun '(df,outval) =>  (Minus df (Number outval)))
                         (list_prod inputFunctions outputs)) in
     (fold_right Plus (Number R0) (map (fun dfj => df_subst f_loss v dfj) losses))
    ).
Proof.
  unfold NNinstance.
  intros.
  rewrite (deltalosses_unique_var H).
  reflexivity.
Qed.

Lemma NNinstance_None (n1 n2 n3 : nat) (ivar : SubVar) (f_loss : DefinedFunction) 
      (NN2 : list DefinedFunction) (inputs : (list R)) 
      (outputs : (list R)) :
  unique_var f_loss = None ->
  NNinstance n1 n2 n3 ivar f_loss NN2 inputs outputs = None.
Proof.
  unfold NNinstance.
  intros.
  rewrite (deltalosses_None H).
  reflexivity.
Qed.

Definition lookup_list (σ:df_env) (lvar : list SubVar) : option (list R) :=
  listo_to_olist (map (fun v => lookup var_dec σ v) lvar).

(* we don't know what a random state type is yet *)
Definition RND_state := Type.

Fixpoint randvecst (n : nat) (st : RND_state ) (randgen : RND_state -> (R * RND_state)) : list (R * RND_state) := 
  match n with
  | 0 => nil
  | S n' => let rst :=  randgen st in
            rst :: randvecst n' (snd rst) randgen
  end.

Definition randvec (n : nat ) (st : RND_state) (randgen : RND_state -> (R * RND_state)) : list (R) * RND_state := 
  let rstlist := randvecst n st randgen in
  (map fst rstlist, snd(last rstlist (R0,st))).

Definition map2 {A:Type} {B:Type} {C:Type} (f: A -> B -> C ) (lA : list A) (lB : list B) : list C :=
  map (fun '(a, b) => f a b) (combine lA lB).

Definition map3 {A:Type} {B:Type} {C:Type} {D:Type} (f: A -> B -> C -> D) (lA : list A) (lB : list B) (lC : list C) : list D :=
  map (fun '(a, bc) => f a (fst bc) (snd bc)) (combine lA (combine lB lC)).

Local Open Scope R.

Definition optimize_step (step : nat) (df : DefinedFunction) (σ:df_env) (lvar : list SubVar) (st : RND_state) (randgen : RND_state -> (R * RND_state)) : (option df_env)*RND_state :=
  let ogradvec := df_eval_gradient σ df lvar in
  let alpha   := / (INR (S step)) in
  let '(noisevec, Rstate) := randvec (length lvar) st randgen in
  let olvals := lookup_list σ lvar in
  match (ogradvec, olvals) with
    | (Some gradvec, Some lvals) => 
      (Some (combine lvar (map3 (fun val grad noise => val - alpha*(grad + noise))
                                lvals gradvec noisevec)), Rstate)
    | (_, _) => (None, Rstate)
  end.                  
