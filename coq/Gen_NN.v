Require Import String.
Require Import RelationClasses.
Require Import Streams.
Require Import List.
Require Import ListAdd.
Require Import Rbase Rtrigo Rpower Rbasic_fun.
Require Import DefinedFunctions.
Require Import Lra.

Require Import FloatishDef Utils.

Section GenNN.

  Context {floatish_impl:floatish}.
  Local Open Scope float.

  Record FullNN : Type := mkNN { ldims : list nat; param_var : SubVar; 
                                 f_activ : DefinedFunction DTfloat; f_loss : DefinedFunction DTfloat }.

  Definition mkSubVarVector (v : SubVar) (n : nat) : DefinedFunction (DTVector n) :=
    DVector (fun i => Var (Sub v (proj1_sig i))).

  Definition mkSubVarMatrix (v : SubVar) (n m : nat) : DefinedFunction (DTMatrix n m) :=
    DMatrix (fun i j => Var (Sub (Sub v (proj1_sig i)) (proj1_sig j))).

  Definition unique_var (df : DefinedFunction DTfloat) : option SubVar :=
    let fv := nodup var_dec (df_free_variables df) in
    match fv with
    | nil => None
    | v :: nil => Some v
    | _ => None
    end.   

  Definition activation (df : DefinedFunction DTfloat) (vec : list (DefinedFunction DTfloat)) : option (list (DefinedFunction DTfloat)) :=
    match unique_var df with
    | Some v => Some (map (fun dfj => df_subst df v dfj) vec)
    | None => None
    end.

  Definition create_activation_fun (df : DefinedFunction DTfloat) : option (DefinedFunction DTfloat -> DefinedFunction DTfloat) :=
    match unique_var df with
    | Some v => Some (fun val => df_subst df v val)
    | None => None
    end.

  Definition mkNN2 (n1 n2 n3 : nat) (ivar wvar : SubVar) (f_activ : DefinedFunction DTfloat) (f_activ_var : SubVar) : (DefinedFunction (DTVector n3)) :=
    let mat1 := mkSubVarMatrix (Sub wvar 1) n2 n1 in
    let mat2 := mkSubVarMatrix (Sub wvar 2) n3 n2 in
    let ivec := mkSubVarVector ivar n1 in
    let N1 := VectorApply f_activ_var f_activ (MatrixVectorMult  mat1 ivec) in 
    VectorApply f_activ_var f_activ (MatrixVectorMult mat2 N1).

  Definition mkNN_bias_step (n1 n2 : nat) (ivec : DefinedFunction (DTVector n1)) 
             (mat : DefinedFunction (DTMatrix n2 n1)) 
             (bias : DefinedFunction (DTVector n2)) 
             (f_activ_var : SubVar) (f_activ : DefinedFunction DTfloat) 
              : DefinedFunction (DTVector n2) :=
    VectorApply f_activ_var f_activ (VectorPlus (MatrixVectorMult mat ivec) bias).


 Definition mkNN2_bias (n1 n2 n3 : nat) (ivar wvar : SubVar) (f_activ : DefinedFunction DTfloat) (f_activ_var : SubVar) : DefinedFunction (DTVector n3) :=
    let mat1 := mkSubVarMatrix (Sub wvar 1) n2 n1 in
    let b1 := mkSubVarVector (Sub wvar 1) n2 in
    let mat2 := mkSubVarMatrix (Sub wvar 2) n3 n2 in
    let b2 := mkSubVarVector (Sub wvar 2) n3 in
    let ivec := mkSubVarVector ivar n1 in
    let N1 := mkNN_bias_step n1 n2 ivec mat1 b1 f_activ_var f_activ in
    mkNN_bias_step n2 n3 N1 mat2 b2 f_activ_var f_activ.

 Lemma vector_float_map_last_rewrite {B nvlist1 n2 v n1} :
   (Vector float (last ((@domain _ B) nvlist1) n2)) = 
   (Vector float (last (domain((n2, v) :: nvlist1)) n1)).
 Proof.
   rewrite domain_cons.
   rewrite last_cons.
   reflexivity.
 Qed.

  Fixpoint mkNN_gen_0 (n1:nat) (nvlist : list (nat * SubVar)) 
           (ivec : (DefinedFunction (DTVector n1)))
           (f_activ_var : SubVar ) (f_activ : DefinedFunction DTfloat) :
    DefinedFunction (DTVector (last (domain nvlist) n1))
:= 
    match nvlist with
    | nil => ivec
    | cons (n2,v) nvlist1 => 
      let mat := mkSubVarMatrix v n2 n1 in
      let b := mkSubVarVector v n2 in
      let N := mkNN_bias_step n1 n2 ivec mat b f_activ_var f_activ in
      eq_rect _ DefinedFunction (mkNN_gen_0 n2 nvlist1 N f_activ_var f_activ) _ vector_float_map_last_rewrite
    end.

  Program Definition mkNN_gen (n1:nat) (nlist : list nat) (ivar wvar f_activ_var : SubVar) 
             (f_activ : DefinedFunction DTfloat) : 
    DefinedFunction (DTVector (last nlist n1)) :=
    let vlist := map (fun i => Sub wvar i) (seq 1 (length nlist)) in
    let ivec := mkSubVarVector ivar n1 in
    eq_rect _ DefinedFunction
            (mkNN_gen_0 n1 (combine nlist vlist) ivec f_activ_var f_activ) _ _.
  Next Obligation.
    f_equal.
    f_equal.
    rewrite combine_domain_eq; trivial.
    now rewrite map_length, seq_length.
  Qed.

  Record testcases : Type := mkTest {ninput: nat; noutput: nat; ntest: nat; 
                                     data : list ((list float) * (list float))}.

  Definition NNinstance (n1 n2 n3 : nat) (ivar : SubVar) (f_loss : DefinedFunction DTfloat) 
             (NN2 : DefinedFunction (DTVector n3)) (inputs : (list float)) 
             (outputs : Vector float n3): option (DefinedFunction DTfloat) :=
    let ipairs := (list_prod (map (fun n => (Sub ivar n)) (seq 1 n1))
                             (map Number inputs)) in
    let losses := VectorMinus (df_subst_list NN2 ipairs) (DVector (vmap Number outputs)) in
    match unique_var f_loss with
    | Some v => Some (VectorSum (VectorApply v f_loss losses))
    | None => None
    end.

  Lemma NNinstance_unique_var (n1 n2 n3 : nat) (ivar : SubVar) (f_loss : DefinedFunction DTfloat) 
        (NN2 : DefinedFunction (DTVector n3)) (inputs : (list float)) 
        (outputs : Vector float n3) (v:SubVar) :
    unique_var f_loss = Some v ->
    NNinstance n1 n2 n3 ivar f_loss NN2 inputs outputs =
    Some (
        let ipairs := (list_prod (map (fun n => (Sub ivar n)) (seq 1 n1))
                                 (map Number inputs)) in
        let losses := VectorMinus (df_subst_list NN2 ipairs) 
                                  (DVector (vmap Number outputs)) in
        (VectorSum (VectorApply v f_loss losses))
      ).
  Proof.
    unfold NNinstance.
    intros.
    rewrite H.
    reflexivity.
  Qed.

  Lemma NNinstance_None (n1 n2 n3 : nat) (ivar : SubVar) (f_loss : DefinedFunction DTfloat) 
        (NN2 : DefinedFunction (DTVector n3)) (inputs : (list float)) 
        (outputs : Vector float n3) :
    unique_var f_loss = None ->
    NNinstance n1 n2 n3 ivar f_loss NN2 inputs outputs = None.
  Proof.
    unfold NNinstance.
    intros.
    now rewrite H.
  Qed.

  Definition lookup_list (σ:df_env) (lvar : list SubVar) : option (list float) :=
    listo_to_olist (map (fun v => lookup var_dec σ v) lvar).

  Definition combine_with {A:Type} {B:Type} {C:Type} (f: A -> B -> C ) (lA : list A) (lB : list B) : list C :=
    map (fun '(a, b) => f a b) (combine lA lB).

  Definition combine3_with {A:Type} {B:Type} {C:Type} {D:Type} (f: A -> B -> C -> D) (lA : list A) (lB : list B) (lC : list C) : list D :=
    map (fun '(a, bc) => f a (fst bc) (snd bc)) (combine lA (combine lB lC)).

  Fixpoint streamtake (n : nat) {A : Type} (st : Stream A) : (list A) * (Stream A) :=
    match n with
    | 0 => (nil, st)
    | S n' => let rst := streamtake n' (Streams.tl st) in
              ((Streams.hd st)::(fst rst), snd rst)
    end.

  Definition update_firstp {A B:Type} (dec:forall a a':A, {a=a'} + {a<>a'}) := fun (l:list (A*B)) '(v,e') => update_first dec l v  e'.

  
  Definition update_list {A B:Type} (dec:forall a a':A, {a=a'} + {a<>a'}) (l up:list (A*B))  : list (A*B)
    := fold_left (update_firstp dec) up l.

  Definition optimize_step (step : nat) (df : DefinedFunction DTfloat) (σ:df_env) (lvar : list SubVar) (noise_st : Stream float) : (option df_env)*(Stream float) :=
    let ogradvec := df_eval_gradient σ df lvar in
    let alpha   :=  1 / (FfromZ (Z.of_nat (S step))) in
    let '(lnoise, nst) := streamtake (length lvar) noise_st in
    let olvals := lookup_list σ lvar in
    match (ogradvec, olvals) with
    | (Some gradvec, Some lvals) => 
      (Some (update_list var_dec σ 
                         (combine lvar (combine3_with 
                                          (fun val grad noise => val - alpha*(grad + noise))
                                          lvals gradvec lnoise))), nst)
    | (_, _) => (None, nst)
    end.

  Fixpoint optimize_steps (start count:nat) (df : DefinedFunction DTfloat) (σ:df_env) (lvar : list SubVar) (noise_st : Stream float) : (option df_env)*(Stream float) :=
    match count with
    | 0 => (Some σ, noise_st)
    | S n =>
      match optimize_step start df σ lvar noise_st with
      | (Some σ', noise_st') => optimize_steps (S start) n df σ' lvar noise_st'
      | (None, noise_st') => (None, noise_st')
      end
    end.

Example xvar := Name "x".
Example xfun:DefinedFunction DTfloat := Var xvar.
Example quad:DefinedFunction DTfloat := Minus (Times xfun xfun) (Number 1).
CoFixpoint noise : Stream float := Cons 0 noise.
Example env : df_env := (xvar, FfromZ 5)::nil.
Example opt := fst (optimize_steps 0 2 quad env (xvar :: nil) noise).
End GenNN.

