----------------------------- MODULE TLAToPCal -----------------------------
EXTENDS Integers, Sequences, TLC


(***************************************************************************)
(* TP Mapping Specifiers                                                   *)
(***************************************************************************)
Location == [line : Nat, column : Nat]
  (*************************************************************************)
  (* This is a location in the file, which might be in the TLA+ spec or in *)
  (* the PCal code.                                                        *)
  (*************************************************************************)

loc1 <: loc2 == 
  (*************************************************************************)
  (* This is the "equals or to the left of" relation on locations.         *)
  (*************************************************************************)
  \/ loc1.line < loc2.line
  \/ /\ loc1.line = loc2.line
     /\ loc1.column =< loc2.column

(***************************************************************************)
(* We define Dist(loc1, loc2) to be a natural number representing a        *)
(* distance between locations loc1 and loc2, assuming loc1 <: loc2.  This  *)
(* distance is used only in the case loc1 <: loc2 <: loc3 to determine if  *)
(* loc2 is closer to loc1 or loc3.  Thus, its magnitude doesn't matter.  I *)
(* should make Dist a parameter of the spec, but it's less effort to give  *)
(* it some reasonable definition.                                          *)
(***************************************************************************)
Dist(loc1, loc2) == 
   1000 * (loc2.line - loc1.line) + (loc2.column - loc1.column)
   
Region == {r \in [begin : Location, end : Location] : r.begin <: r.end}
  (*************************************************************************)
  (* This describes a region within the file.  We say that region r1 is to *)
  (* the left of region r2 iff r1.end :< r2.begin                          *)
  (*************************************************************************)

(***************************************************************************)
(* TLA to PCal translation objects.                                        *)
(***************************************************************************)
TLAToken == [type : {"token"}, region  : Region]
  (*************************************************************************)
  (* This represents a region in the TLA+ spec.                            *)
  (*************************************************************************)
Paren    == [type : {"begin", "end"}, loc : Location]
  (*************************************************************************)
  (* This represents the beginning or end of a region in the PlusCal spec. *)
  (*************************************************************************)
Break    == [type : {"break"}, depth : Nat]
  (*************************************************************************)
  (* A Break comes between a right and left Paren at the same parenthesis  *)
  (* level (possibly with TLATokens also between them).  It indicates that *)
  (* there is some PlusCal code between the locations indicated by those   *)
  (* parentheses that should not be displayed when displaying the PlusCal  *)
  (* code for parenthesis levels between the current level lv and lv -     *)
  (* depth.                                                                *)
  (*************************************************************************)
TPObject == TLAToken \cup Paren \cup Break

RECURSIVE ParenDepth(_ , _)
ParenDepth(objSeq, pos) ==
  (*************************************************************************)
  (* Equals the parenthesis depth of the point in the TPObject sequence    *)
  (* objSeq just after element number pos, or at the beginning if pos = 0. *)
  (*************************************************************************)
  IF pos = 0 THEN 0
             ELSE LET obj == objSeq[pos]
                  IN  ParenDepth(objSeq, pos - 1) +
                        ( CASE obj.type = "begin" -> 1  []
                               obj.type = "end"   -> -1 []
                               OTHER              -> 0     )

(***************************************************************************)
(* WellFormed(seq) is true for a TPObject sequence iff it begins and ends  *)
(* with a parenthesis and all parentheses are properly matching.           *)
(***************************************************************************)
IsWellFormed(seq) ==  /\ seq # << >>
                      /\ seq[1].type = "begin"
                      /\ \A i \in 1..(Len(seq)-1) : ParenDepth(seq, i) >= 0
                      /\ ParenDepth(seq, Len(seq)) = 0

(***************************************************************************)
(* TokensInOrder(seq) is true for a TPObject sequence iff its TLAToken     *)
(* objects represent regions that are ordered properly--that is, if        *)
(* TLAToken T1 precedes TLAToken T2 in seq, then T1.region is to the left  *)
(* of T2.region.                                                           *)
(***************************************************************************)                      
TokensInOrder(seq) ==
  \A i \in 1..Len(seq) : 
     (seq[i].type = "token") => 
        \A j \in (i+1)..Len(seq) : 
           (seq[j].type = "token") =>
              (seq[i].region.end <: seq[j].region.begin)

MatchingParen(seq, pos) ==
  (*************************************************************************)
  (* If element number pos in TPObject sequence seq is a left paren, then  *)
  (* this equals the number n such that element number n is the matching   *)
  (* right paren.                                                          *)
  (*************************************************************************)
  CHOOSE i \in pos+1..Len(seq) :
     /\ ParenDepth(seq,i) = ParenDepth(seq, pos-1)
     /\ \A j \in (pos)..(i-1) : ParenDepth(seq, j) > ParenDepth(seq, pos-1)

(***************************************************************************)
(* A TPSpec is a sequence of TPObject elements that has the following      *)
(* interpretation.  The regions of the TLA+ spec contained within its      *)
(* TLAToken elements contain the "important" text of the spec.  Text not   *)
(* in those regions can be treated as if it were white space when          *)
(* determining the PCal region that maps to a part of the TLA+ spec.       *)
(*                                                                         *)
(* Each pair of matching parentheses defines the smallest syntactic unit   *)
(* (e.g., expression or statement) whose translation contains the text in  *)
(* the TLATokens between them.  All the top level (lowest depth)           *)
(* parentheses between those matching parentheses describe successive      *)
(* regions in the same part of the PCal text.  (Code in a macro and code   *)
(* in a procedure is an example of two regions in completely different     *)
(* parts of the PCal code, and hence are not successive regions.) Two      *)
(* successive regions are adjacent if, to higlight both of them, one       *)
(* highlights those regions and the text between them.  If two successive  *)
(* regions represented by two pairs of matching parentheses are not        *)
(* adjacent, then the TPSpec contains a Break between them.  The depth of  *)
(* a break indicates the number of parenthesis levels containing the break *)
(* that represent PCal code in which the region between the parenthesized  *)
(* regions on either side of the break should not be highlighted.          *)
(*                                                                         *)
(* The following predicate asserts that seq is a proper TPSpec.            *)
(***************************************************************************)
IsTPSpec(seq) ==
   (************************************************************************)
   (* There is at least one TLAToken between every matching pair of        *)
   (* parentheses.                                                         *)
   (************************************************************************)
   /\ \A i \in 1..Len(seq) :
         (seq[i].type = "begin") =>
            \E j \in (i+1)..(MatchingParen(seq,i)-1) : seq[j].type = "token"
   /\ IsWellFormed(seq)
   /\ TokensInOrder(seq)
   (************************************************************************)
   (* The following conjunct asserts that a Break comes between a right    *)
   (* and a left parenthesis at its level, perhaps with intervening        *)
   (* tokens.                                                              *)
   (************************************************************************) 
   /\ \A i \in 1..Len(seq) :
         (seq[i].type = "break") => 
            /\ \E j \in 1..(i-1) : 
                  /\ seq[j].type = "end"
                  /\ \A k \in (j+1)..(i-1) : seq[j].type # "begin"
            /\  \E j \in (i+1)..Len(seq) : 
                  /\ seq[j].type = "begin"
                  /\ \A k \in (i+1)..(j-1) : seq[j].type # "end"
   (************************************************************************)
   (* The following conjunct asserts that matching parentheses have        *)
   (* non-decreasing locations, and that within a pair of matched          *)
   (* parentheses, the regions represented by the top-level matching       *)
   (* parentheses are properly ordered.                                    *)
   (************************************************************************)
   /\ \A i \in 1..Len(seq) :
         (seq[i].type = "begin") =>
            LET j  == MatchingParen(seq, i)
                dp == ParenDepth(seq, i-1) + 1
            IN  /\ seq[i].loc <: seq[j].loc
                /\ \A k \in (i+1)..(j-1) :
                     /\ seq[k].type = "end"
                     /\ ParenDepth(seq, k) = dp
                     => \A m \in (k+1)..(j-1) :
                          /\ seq[m].type = "begin"
                          /\ ParenDepth(seq, m-1) = dp
                          => seq[k].loc <: seq[m].loc

TPSpec == {s \in Seq(TPObject) : IsTPSpec(s)}           
-----------------------------------------------------------------------------
(***************************************************************************)
(* The Region in the PCal code specified by a Region in the TLA+ spec.     *)
(***************************************************************************)

Min(S) == IF S = {} THEN -1 ELSE CHOOSE i \in S : \A j \in S : i =< j
Max(S) == IF S = {} THEN -1 ELSE CHOOSE i \in S : \A j \in S : i >= j

RegionToTokPair(spec, reg) ==
  (*************************************************************************)
  (* A pair of integers that are the positions of the pair of TLATokens in *)
  (* spec such that they and the TLATokens between them are the ones that  *)
  (* the user has chosen if she has highlighted the region specified by    *)
  (* reg.  (Both tokens could be the same.)                                *)
  (*                                                                       *)
  (* If the region reg does not intersect with the region of any TLAToken  *)
  (* (so it lies entirely inside "white space"), then the value is <<t,    *)
  (* t>> for the token t that lies either to the left or the right of reg. *)
  (*************************************************************************)
  LET Dom == 1..Len(spec)
  
      InTokens(loc) == {i \in Dom : /\ spec[i].region.begin <: loc
                                    /\ loc <: spec[i].region.end}
      TokToLeft(loc) == 
        (*******************************************************************)
        (* The position of the right-most token whose beginning is at or   *)
        (* to the left of loc, or -1 if there is none.                     *)
        (*******************************************************************)
        Max({i \in Dom : /\ spec[i].type = "token"
                         /\ spec[i].region.begin <: loc})

      TokToRight(loc) ==
        (*******************************************************************)
        (* The position of the left-most token whose end is at or to the   *)
        (* right of loc, or -1 if there is none.                           *)
        (*******************************************************************)
        Min({i \in Dom : /\ spec[i].type = "token"
                         /\ loc <: spec[i].region.end})
      
      lt == IF InTokens(reg.begin) # {}
              THEN Max(InTokens(reg.begin))
              ELSE TokToRight(reg.begin)
      
      rt == IF InTokens(reg.end) # {}
              THEN Min(InTokens(reg.end))
              ELSE TokToLeft(reg.begin)
      
  IN  TRUE
 
              
   (****** 
   This def is screwed up.
   
        (***************************************************************
In this case, rt # -1 and lt.region is equal to or to the
left of rt.region.  In this case, we return <<lt, rt>>
except in the special case when the two regions touch
(spec[lt].region.end equal to spec[rt].region.begin) and
one of the endpoints of reg equals the location at which
they touch.  In that case, we just return one of the
regions.  If reg consists just of that point, then we
return both tokens.

This fails if one but not both ends of reg are at the boundary
where two tokens touch.  
             ***************************************************************)
             IF spec[lt].region.end = spec[rt].region.begin
               THEN IF spec[lt].region.end = reg.begin
                      THEN IF spec[rt].region.begin # reg.end
                             THEN <<rt, rt>>
                             ELSE <<lt, rt>>
                      ELSE IF spec[rt].region.begin = reg.end
                             THEN <<lt, lt>>
                             ELSE <<lt, rt>>
               ELSE << lt, rt >>
        ELSE IF lt = -1 
               THEN (*******************************************************)
                    (* In this case, rt # -1 and region reg is to the      *)
                    (* right of all TLAToken regions of spec and rt is the *)
                    (* left-most token of spec.                            *)
                    (*******************************************************)
                    <<rt, rt>>
               ELSE IF rt = -1
                      THEN (************************************************)
                           (* In this case, lt # 1 and region reg is to    *)
                           (* the left of all TLAToken regions of spec and *)
                           (* lt is the position of the right-most token   *)
                           (* of spec.                                     *)
                           (************************************************)
                           <<lt, lt>>
                      ELSE (************************************************)
                           (* In this case region, rt.region is to the     *)
                           (* left of reg and reg is to the left of        *)
                           (* lt.region, and we use the token that's       *)
                           (* closest.  (This seems to work out better     *)
                           (* than to take both the tokens.)               *)
                           (************************************************)
                           IF Dist(spec[rt].region.end, reg.begin) < 
                                 Dist(reg.end, spec[lt].region.begin)
                             THEN <<rt, rt>>
                             ELSE <<lt, lt>>                          
**********)

TokPairToParens(spec, ltok, rtok) ==
  (*************************************************************************)
  (* Assumes ltok and rtok are the positions of TLAToken elements of the   *)
  (* TPSpec spec with ltok equal to or to the left of rtok.  It equals the *)
  (* pair <<lparen, rparen>> where lparen is the position of the           *)
  (* right-most left paren to the left of ltok that leaves level dp and    *)
  (* rparen is the position of the left-most right paren to the right of   *)
  (* rtok that enters level dp, where dp is the lowest paren depth of any  *)
  (* token from ltok and rtok.                                             *)
  (*************************************************************************)
  LET dp == Min ( {ParenDepth(spec, i) : 
                     i \in {j \in ltok..rtok : spec[j].type = "token"}} )
      lp == Max ( {i \in 1..ltok : /\ spec[i].type = "begin"
                                   /\ ParenDepth(spec,i) = dp} )
      rp == Min ( {i \in rtok..Len(spec) : /\ spec[i].type = "end"
                                           /\ ParenDepth(spec,i-1) = dp} )
  IN  <<lp, rp>>
-----------------------------------------------------------------------------
(***************************************************************************)
(* For Debugging                                                           *)
(*                                                                         *)
(* To simplify debugging, we assume that locations are all on the same     *)
(* line.                                                                   *)
(***************************************************************************)
Loc(pos) == [line |-> 0, column |-> pos]
Reg(beg, end) == [begin |-> Loc(beg), end |-> Loc(end)]
T(beg, end) == [type |->"token", region |-> Reg(beg, end)]
L(pos) == [type |-> "begin", loc |-> Loc(pos)]
R(pos) == [type |-> "end", loc |-> Loc(pos)]
B(dep) == [type |-> "break", depth |-> dep]

tpSpec1 == << L(-5), T(2,3), L(11), T(3, 4), L(12), T(4,5), R(13), 
              T(6,7), R(14), T(8, 9), R(42) >>
tpRegion1 == Reg(5,20)
-----------------------------------------------------------------------------
(***************************************************************************)
(* Declare tpSpec to be the TPSpec and tpLoc the Location that are the     *)
(* inputs to the algorithm.                                                *)
(***************************************************************************)
CONSTANT tpSpec, tpRegion
  
(***************************************************************************
                          The Mapping Algorithm
                          
--fair algorithm Map {
    variables  
        tpregion \* = tpRegion , \* use the variable instead of tpRegion 
                               \* to allow debugging 
                   \in { Reg(r[1], r[2]) : 
                             r \in {rr \in (1..10)\X(1..10) : 
                                       rr[1] =< rr[2]} } ,
        ltok,      \* <<ltok, rtok>> is set to 
        rtok,      \* RegionToTokPair(tpSpec, tpregion)
        rtokDepth, \* The paren depth of rtok relative to ltok
        minDepth,  \* The depth of the minimum paren depth TLAToken               
        bParen,    \* <<bParen, eParen>> is set to 
        eParen,    \* TokPairToParens(tpSpec, ltok, rtok)
        result,    \* The sequence of Regions representing that
                   \* is the translation.
        curBegin,  \* Used to construct the result
        lastRparen,\*  "    
        i,         \* For loop variable
        curDepth   \* Temporary variable for holding the paren depth
    ;  
    macro ModifyDepth(var, pos, movingForward) {
      \* If var is the parenthesis depth of the token at position pos
      \* then this sets var to the parenthesis depth of the token at
      \* position pos + 1 if movingForward = TRUE, else the depth
      \* at pos - 1 if movingForward = FALSE.
       with (amt = CASE tpSpec[pos].type = "begin" ->  1  []
                        tpSpec[pos].type = "end"   -> -1 []
                        OTHER                    -> 0     ) {
           var := var + IF movingForward THEN amt ELSE -amt
        }
      }
      
    { with (tp = RegionToTokPair(tpSpec, tpregion)) {
         ltok := tp[1];
         rtok := tp[2]
       } ;
       
      \* If d is the depth of ltok, then set rtokDepth and minDepth
      \* such that d + rtokDepth is the depth of rtok and
      \* d + minDepth is the minimum depth of tokens
      rtokDepth := 0;
      minDepth := 0 ;
      i := ltok+1;
      while (i =< rtok) {
         ModifyDepth(rtokDepth, i, TRUE);
         if (rtokDepth < minDepth) {minDepth := rtokDepth} ;
         i := i+1
       };
      assert /\ ParenDepth(tpSpec, rtok) = ParenDepth(tpSpec, ltok) + rtokDepth
             /\ minDepth + ParenDepth(tpSpec, ltok) =
                  Min({ParenDepth(tpSpec, k) : k \in ltok..rtok}) ;
      
      \* set bParen to first left paren to left of ltok that
      \* descends to relative paren depth minDepth
      curDepth := 0;
      i := ltok - 1;
      while (~ /\ tpSpec[i].type = "begin"
               /\ curDepth = minDepth ) {
        ModifyDepth(curDepth, i, FALSE) ;
        i := i-1
       } ;
      bParen := i ;
      
      \* set eParen to first right paren to the right of rtok that
      \* rises from relative paren depth minDepth
      curDepth := rtokDepth;
      i := rtok + 1;
      while (~ /\ tpSpec[i].type = "end"
               /\ curDepth = minDepth ) {
        ModifyDepth(curDepth, i, TRUE) ;
        i := i+1
       } ;
      eParen := i ;
      assert <<bParen, eParen>> = TokPairToParens(tpSpec, ltok, rtok);
      
      \* Construct the final result
      result := << >> ; 
      curBegin := tpSpec[bParen].loc ;
      curDepth := 0 ;
      lastRparen := -1 ;
      i := bParen + 1 ;
      while (i < eParen) {
        if (tpSpec[i].type = "end") {
          lastRparen := i
          } ;
        if ( /\ tpSpec[i].type = "break"
             /\ tpSpec[i].depth - curDepth >= 0 ) {
             assert lastRparen # -1 ;
             lastRparen := -1 ;
             result := Append(result, 
                              [begin |-> curBegin, end |-> tpSpec[lastRparen].loc]);
             while (tpSpec[i].type # "begin") {
               ModifyDepth(curDepth, i, TRUE) ;
               i := i+1;
              } ;
             curBegin := tpSpec[i].loc ;         
           } ;
        ModifyDepth(curDepth, i, TRUE) ;
        i := i+1;
       } ;
      result := Append(result, 
                       [begin |-> curBegin, end |-> tpSpec[eParen].loc]);
       
      print <<tpregion.begin.column, tpregion.end.column>> ;
      print [j \in 1..Len(result) |-> <<result[j].begin.column,
                                        result[j].end.column>>];
      print << "lrtok", ltok, rtok>>
    }
}
 ***************************************************************************)
\* BEGIN TRANSLATION
CONSTANT defaultInitValue
VARIABLES tpregion, ltok, rtok, rtokDepth, minDepth, bParen, eParen, result, 
          curBegin, lastRparen, i, curDepth, pc

vars == << tpregion, ltok, rtok, rtokDepth, minDepth, bParen, eParen, result, 
           curBegin, lastRparen, i, curDepth, pc >>

Init == (* Global variables *)
        /\ tpregion \in { Reg(r[1], r[2]) :
                              r \in {rr \in (1..10)\X(1..10) :
                                        rr[1] =< rr[2]} }
        /\ ltok = defaultInitValue
        /\ rtok = defaultInitValue
        /\ rtokDepth = defaultInitValue
        /\ minDepth = defaultInitValue
        /\ bParen = defaultInitValue
        /\ eParen = defaultInitValue
        /\ result = defaultInitValue
        /\ curBegin = defaultInitValue
        /\ lastRparen = defaultInitValue
        /\ i = defaultInitValue
        /\ curDepth = defaultInitValue
        /\ pc = "Lbl_1"

Lbl_1 == /\ pc = "Lbl_1"
         /\ LET tp == RegionToTokPair(tpSpec, tpregion) IN
              /\ ltok' = tp[1]
              /\ rtok' = tp[2]
         /\ rtokDepth' = 0
         /\ minDepth' = 0
         /\ i' = ltok'+1
         /\ pc' = "Lbl_2"
         /\ UNCHANGED << tpregion, bParen, eParen, result, curBegin, 
                         lastRparen, curDepth >>

Lbl_2 == /\ pc = "Lbl_2"
         /\ IF i =< rtok
               THEN /\ LET amt == CASE tpSpec[i].type = "begin" ->  1  []
                                       tpSpec[i].type = "end"   -> -1 []
                                       OTHER                    -> 0 IN
                         rtokDepth' = rtokDepth + IF TRUE THEN amt ELSE -amt
                    /\ IF rtokDepth' < minDepth
                          THEN /\ minDepth' = rtokDepth'
                          ELSE /\ TRUE
                               /\ UNCHANGED minDepth
                    /\ i' = i+1
                    /\ pc' = "Lbl_2"
                    /\ UNCHANGED curDepth
               ELSE /\ Assert(/\ ParenDepth(tpSpec, rtok) = ParenDepth(tpSpec, ltok) + rtokDepth
                              /\ minDepth + ParenDepth(tpSpec, ltok) =
                                   Min({ParenDepth(tpSpec, k) : k \in ltok..rtok}), 
                              "Failure of assertion at line 352, column 7.")
                    /\ curDepth' = 0
                    /\ i' = ltok - 1
                    /\ pc' = "Lbl_3"
                    /\ UNCHANGED << rtokDepth, minDepth >>
         /\ UNCHANGED << tpregion, ltok, rtok, bParen, eParen, result, 
                         curBegin, lastRparen >>

Lbl_3 == /\ pc = "Lbl_3"
         /\ IF ~ /\ tpSpec[i].type = "begin"
                 /\ curDepth = minDepth
               THEN /\ LET amt == CASE tpSpec[i].type = "begin" ->  1  []
                                       tpSpec[i].type = "end"   -> -1 []
                                       OTHER                    -> 0 IN
                         curDepth' = curDepth + IF FALSE THEN amt ELSE -amt
                    /\ i' = i-1
                    /\ pc' = "Lbl_3"
                    /\ UNCHANGED bParen
               ELSE /\ bParen' = i
                    /\ curDepth' = rtokDepth
                    /\ i' = rtok + 1
                    /\ pc' = "Lbl_4"
         /\ UNCHANGED << tpregion, ltok, rtok, rtokDepth, minDepth, eParen, 
                         result, curBegin, lastRparen >>

Lbl_4 == /\ pc = "Lbl_4"
         /\ IF ~ /\ tpSpec[i].type = "end"
                 /\ curDepth = minDepth
               THEN /\ LET amt == CASE tpSpec[i].type = "begin" ->  1  []
                                       tpSpec[i].type = "end"   -> -1 []
                                       OTHER                    -> 0 IN
                         curDepth' = curDepth + IF TRUE THEN amt ELSE -amt
                    /\ i' = i+1
                    /\ pc' = "Lbl_4"
                    /\ UNCHANGED << eParen, result, curBegin, lastRparen >>
               ELSE /\ eParen' = i
                    /\ Assert(<<bParen, eParen'>> = TokPairToParens(tpSpec, ltok, rtok), 
                              "Failure of assertion at line 377, column 7.")
                    /\ result' = << >>
                    /\ curBegin' = tpSpec[bParen].loc
                    /\ curDepth' = 0
                    /\ lastRparen' = -1
                    /\ i' = bParen + 1
                    /\ pc' = "Lbl_5"
         /\ UNCHANGED << tpregion, ltok, rtok, rtokDepth, minDepth, bParen >>

Lbl_5 == /\ pc = "Lbl_5"
         /\ IF i < eParen
               THEN /\ IF tpSpec[i].type = "end"
                          THEN /\ lastRparen' = i
                          ELSE /\ TRUE
                               /\ UNCHANGED lastRparen
                    /\ IF /\ tpSpec[i].type = "break"
                          /\ tpSpec[i].depth - curDepth >= 0
                          THEN /\ Assert(lastRparen' # -1, 
                                         "Failure of assertion at line 391, column 14.")
                               /\ pc' = "Lbl_6"
                          ELSE /\ pc' = "Lbl_8"
                    /\ UNCHANGED result
               ELSE /\ result' = Append(result,
                                        [begin |-> curBegin, end |-> tpSpec[eParen].loc])
                    /\ PrintT(<<tpregion.begin.column, tpregion.end.column>>)
                    /\ PrintT([j \in 1..Len(result') |-> <<result'[j].begin.column,
                                                           result'[j].end.column>>])
                    /\ PrintT(<< "lrtok", ltok, rtok>>)
                    /\ pc' = "Done"
                    /\ UNCHANGED lastRparen
         /\ UNCHANGED << tpregion, ltok, rtok, rtokDepth, minDepth, bParen, 
                         eParen, curBegin, i, curDepth >>

Lbl_8 == /\ pc = "Lbl_8"
         /\ LET amt == CASE tpSpec[i].type = "begin" ->  1  []
                            tpSpec[i].type = "end"   -> -1 []
                            OTHER                    -> 0 IN
              curDepth' = curDepth + IF TRUE THEN amt ELSE -amt
         /\ i' = i+1
         /\ pc' = "Lbl_5"
         /\ UNCHANGED << tpregion, ltok, rtok, rtokDepth, minDepth, bParen, 
                         eParen, result, curBegin, lastRparen >>

Lbl_6 == /\ pc = "Lbl_6"
         /\ lastRparen' = -1
         /\ result' = Append(result,
                             [begin |-> curBegin, end |-> tpSpec[lastRparen'].loc])
         /\ pc' = "Lbl_7"
         /\ UNCHANGED << tpregion, ltok, rtok, rtokDepth, minDepth, bParen, 
                         eParen, curBegin, i, curDepth >>

Lbl_7 == /\ pc = "Lbl_7"
         /\ IF tpSpec[i].type # "begin"
               THEN /\ LET amt == CASE tpSpec[i].type = "begin" ->  1  []
                                       tpSpec[i].type = "end"   -> -1 []
                                       OTHER                    -> 0 IN
                         curDepth' = curDepth + IF TRUE THEN amt ELSE -amt
                    /\ i' = i+1
                    /\ pc' = "Lbl_7"
                    /\ UNCHANGED curBegin
               ELSE /\ curBegin' = tpSpec[i].loc
                    /\ pc' = "Lbl_8"
                    /\ UNCHANGED << i, curDepth >>
         /\ UNCHANGED << tpregion, ltok, rtok, rtokDepth, minDepth, bParen, 
                         eParen, result, lastRparen >>

Next == Lbl_1 \/ Lbl_2 \/ Lbl_3 \/ Lbl_4 \/ Lbl_5 \/ Lbl_8 \/ Lbl_6
           \/ Lbl_7
           \/ (* Disjunct to prevent deadlock on termination *)
              (pc = "Done" /\ UNCHANGED vars)

Spec == /\ Init /\ [][Next]_vars
        /\ WF_vars(Next)

Termination == <>(pc = "Done")

\* END TRANSLATION

=============================================================================
\* Modification History
\* Last modified Fri Dec 02 19:27:10 PST 2011 by lamport
\* Created Thu Dec 01 16:51:23 PST 2011 by lamport