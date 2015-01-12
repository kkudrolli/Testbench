/* 
 * top.sv
 *
 * Author:   Kais Kudrolli
 * AndrewID: kkudroll
 *
 * This file contains the testbench for a reverse polish notation
 * calculator provided in TA_calc_broken.svp and TA_calc_golden.svp.
 * It uses an always_ff block to create a model for the calculator,
 * that is it keeps track of the calculator state and checks this 
 * state against the actual values in the calculator. The RPN 
 * calculator was a black box during testing. Testing was done 
 * mainly by sending test vectors into the calculator and verifying
 * the outputs from the calculator with concurrent assertions. A 
 * combination of direct and random testing is employed in this tb.
 */

`ifndef STRUCTS
`define STRUCTS
    typedef enum bit [3:0] {
        start   = 4'h1, 
        enter   = 4'h2, 
        arithOp = 4'h4, 
        done    = 4'h8
    } oper;

    typedef struct packed {
        oper       op;
        bit [15:0] payload;
    } keyIn;
`endif

///////////////////
////           ////
////    top    ////
////           ////
///////////////////

module top();

    ////////////////////
    // Random classes //
    ////////////////////

    // Generates random positive 2's complement values
    class randomPosVals;
        rand bit [15:0] payloadA;
        rand bit [15:0] payloadB;
        
        constraint posA {payloadA inside {[0:32767]};} // Can overflow with add 
        constraint posB {payloadB inside {[0:32767]};}
    endclass: randomPosVals
    
    // Generates positive values small enough that adding any two of them
    // will not result in overflow
    class noOverflowVals;
        rand bit [15:0] payloadA;
        rand bit [15:0] payloadB;
        
        constraint posA {payloadA inside {[0:16383]};} // Can't overflow with add 
        constraint posB {payloadB inside {[0:16383]};}
    endclass: noOverflowVals
   
    // Generates two random operands and an operation to be performed on these
    // operands
    class randomTwoOperand;
        rand bit [15:0] A;
        rand bit [15:0] B;
        rand bit [15:0] op;
        
        constraint opA {op inside {1, 2, 4, 8, 32};}
    endclass: randomTwoOperand

    // Randomly chooses an add, subtract, or and
    class randomOper;
        rand bit [15:0] op;

        constraint opA {op inside {1, 2, 4};} // no swap
    endclass: randomOper

    // Generates a random operation and payload. This is used 
    // do give the calculator fully random inputs.
    class randomAll;
        rand bit [15:0] payload;
        rand bit [3:0]  op;
    endclass: randomAll

    // Generates a random number of iterations for a loop. 
    class randomIters;
        rand bit [3:0] numIters;
    endclass
 
    // Instantiate random objects
    randomPosVals rvals = new;
    noOverflowVals noOver = new;
    randomTwoOperand r2op = new;
    randomOper rop = new;
    randomAll rall = new;
    randomIters riters = new;

    ///////////////////////
    // Signals and wires //
    ///////////////////////

    // Queue and queue state
    bit [15:0] q[$];
    int        q_size;

    // Inputs to calculator
    bit    ck, rst_l;
    keyIn  data, inData;

    // Outputs from calculator
    bit [15:0]  result;
    bit         stackOverflow, unexpectedDone, protocolError, dataOverflow, 
                correct, finished;

    // Internal signals and registers
    bit [15:0] myResult, tempA, tempB, tempResult;
    bit        overflow;
    bit [4:0]  doneBehavior;
    
    ///////////////////////
    // Other misc. setup //
    ///////////////////////

    // Calculator instantiation
    TA_calc  brokenCalc(.*);

    // Default clocking block
    default clocking myClock
        @(posedge ck);
    endclocking

    // The system clock
    initial begin
        ck = 0;
        forever #5 ck = ~ck;
    end

    ///////////////////////////////
    // Functional Coverage Setup //
    ///////////////////////////////

    // Correct is asserted a number of times 
    covergroup correctCheck @(posedge ck);
        option.at_least = 100;
        coverpoint correct {
            bins low  = {0};
            bins high = {1};
        } 
    endgroup: correctCheck

    // Cover group to ensure operations sent to calculator is varied
    covergroup variedOps @(posedge ck);
        option.at_least = 10;
        coverpoint data.payload iff (data.op == arithOp) {
            bins add   = {16'h1}; 
            bins sub   = {16'h2}; 
            bins andOp = {16'h4}; 
            bins swap  = {16'h8}; 
            bins neg   = {16'h10}; 
            bins pop   = {16'h20}; 
        } 
    endgroup: variedOps

    // Cover group to ensure data sent to calculator is varied
    covergroup variedData @(posedge ck);
        option.at_least = 20;
        coverpoint data.payload iff (data.op == start || data.op == enter) {
            bins a0 = {[16'h0    : 16'h10]};
            bins a1 = {[16'h11   : 16'h100]};
            bins a2 = {[16'h101  : 16'h1000]};
            bins a3 = {[16'h1001 : 16'hf000]};
            bins a4 = {[16'hf001 : 16'hffff]};
        }
    endgroup: variedData

    // Cover group to ensure protocol error is checked a number of times
    covergroup coverProtocol with function sample();
        option.at_least = 20;
        coverpoint protocolError {
            bins high = {1};
        }
    endgroup: coverProtocol

    // Instantiate all covergroups
    correctCheck cc = new;
    variedOps vops = new;
    variedData vdata = new;
    coverProtocol cprot = new;

    ///////////////
    // Testbench //
    ///////////////

    // This task contains the testbench.
    // The input phase is the phase of the broken calculator tests.
    task runTestbench(input int phase);
        begin

        // My testbench runs below here. A series of tasks are called to input
        // many different sequences of test vectors into the calculator. The
        // test come in several phases that either test for a specific fault 
        // or perform random testing.

        $display("///////////");
        $display("// RESET //");
        $display("///////////\n");

        rst_l <= 0;
        @(posedge ck);
        rst_l <= 1;
        @(posedge ck);
    
        $display("////////////////");
        $display("// SIMPLE ADD //");
        $display("////////////////\n");

        simpleAddNoOverflow();
        simpleAddNoOverflow();

        simpleAdd();
        
        $display("/////////////////////////////");
        $display("// SIMPLE RANDOM OPERATION //");
        $display("/////////////////////////////\n");

        for (int i = 0; i < 100; i++) begin
            simpleRandOper();
        end

        $display("///////////////////");
        $display("// SIMPLE NEGATE //");
        $display("///////////////////\n");

        for (int i = 0; i < 100; i++) begin
            simpleNegate();
        end

        $display("/////////////////////");
        $display("// STUCK AT ERRORS //");
        $display("/////////////////////\n");

        stuckAt0();
        stuckAt1();

        $display("////////////////////");
        $display("// STACK OVERFLOW //");
        $display("////////////////////\n");

        overflowStack();

        $display("///////////////////////");
        $display("// POP WITH NO ELEMS //");
        $display("///////////////////////\n");
 
        pop_no_elems();

        $display("///////////////////////");
        $display("// ADD WITH ONE ELEM //");
        $display("///////////////////////\n");

        addOneElem();

        $display("///////////////////////");
        $display("// UNEXPECTED START  //");
        $display("///////////////////////\n");

        unexpectedStart();

        $display("/////////////////////");
        $display("// CHECK OVERFLOW  //");
        $display("/////////////////////\n");

        makeOverflow();
        overflowEdge();
        
        $display("/////////////////////");
        $display("// INVALID COMMAND //");
        $display("/////////////////////\n");

        sendInvalidCmd();

        $display("///////////////////////");
        $display("// INVALID OPERATION //");
        $display("///////////////////////\n");

        sendInvalidOp();

        $display("/////////////////////");
        $display("// UNEXPECTED DONE //");
        $display("/////////////////////\n");

        createUnexpectedDone();

        $display("/////////////////");
        $display("// EMPTY STACK //");
        $display("/////////////////\n");

        emptyTheStack();

        $display("///////////////////");
        $display("// IGNORE INPUTS //");
        $display("///////////////////\n");

        ignoreInputs();
        
        $display("//////////////////////////////");
        $display("// R/W EVERY STACK LOCATION //");
        $display("//////////////////////////////\n");

        addAllElems();

        $display("/////////////////////");
        $display("// RANDOM SEQUENCE //");
        $display("/////////////////////\n");

        for (int i = 0; i < 100; i++) randomSequence();
        
        $display("////////////////");
        $display("// CHECK SWAP //");
        $display("////////////////\n");

        checkSwap();
        
        end
    endtask: runTestbench

    ///////////
    // Final //
    ///////////

    // Final block that displays functional coverage statistics
    final begin
        $display("\nFunctional Coverage Statistics");
        $display("-------------------------------\n");

        $display("Correct Check Coverage: %0.3f", cc.get_coverage());
        $display("Varied Ops Coverage: %0.3f", vops.get_coverage());
        $display("Varied Data Coverage: %0.3f", vdata.get_coverage());
        $display("Protocol Error Coverage: %0.3f", cprot.get_coverage());
        $display("Total Coverage: %0.3f\n", $get_coverage());
        
    end

    //////////////////////
    // Calculator Model //
    //////////////////////

    // This is the calculator model. It looks at the value on the data lines
    // at each clock edge and appropriately updates the state of the queue,
    // updates the queue size, and keeps track of overflow internally in the
    // testbench. The purpose of this is to use this tracked state as a 
    // reference against the calculator outputs.
    always_ff @(posedge ck, negedge rst_l) begin
        if (~rst_l) begin
            q_size <= 'd0;
            tempA <= 'd0;
            tempB <= 'd0;
            overflow <= 0;
            data <= 'd0;
        end
        else begin
            data <= inData;
            case (inData.op)
                start: begin
                    q.push_front(inData.payload);
                    q_size <= q_size + 1;;
                end
                enter: begin
                    q.push_front(inData.payload);
                    q_size <= q_size + 1;;
                end
                arithOp: begin
                    case (inData.payload) 
                        1: begin // add
                            tempA = q.pop_front(); // Blocking assignments 
                            tempB = q.pop_front(); // used in always_ff to 
                                                   // update before clock edge
                            tempResult = tempA + tempB;
                            q.push_front(tempA + tempB);
                            // Set overflow
                            if (tempA[15] == 0 && tempB[15] == 0 && tempResult[15] == 1) overflow <= 1;
                            else if (tempA[15] == 1 && tempB[15] == 1 && tempResult[15] == 0) overflow <= 1;
                            else overflow <= 0;
                            q_size <= q_size - 1;
                        end 
                        2: begin // subtract
                            tempA = q.pop_front();
                            tempB = q.pop_front();
                            tempResult = tempB - tempA;
                            q.push_front(tempB - tempA);
                            // Set overflow
                            if (tempA[15] == 1 && tempB[15] == 0 && tempResult[15] == 1) overflow <= 1;
                            else if (tempA[15] == 0 && tempB[15] == 1 && tempResult[15] == 0) overflow <= 1;
                            else overflow <= 0;
                            q_size <= q_size - 1;
                        end
                        4: begin // and
                            tempA = q.pop_front();
                            tempB = q.pop_front();
                            q.push_front(tempA & tempB);
                            q_size <= q_size - 1;
                        end
                        8: begin // swap
                            tempA = q.pop_front();
                            tempB = q.pop_front();
                            q.push_front(tempA);
                            q.push_front(tempB);
                        end
                        16: begin // negate
                            q.push_front((~q.pop_front()) + 1);
                        end
                        32: begin // pop
                            myResult <= q.pop_front();
                            q_size <= q_size - 1;
                        end
                    endcase
                end
                done: begin
                    overflow <= 0;
                    // There are multiple behaviors when a done is called 
                    // depending on the test being run. The different behaviors
                    // ensure the state is zeroed out after each test.
                    case (doneBehavior)
                        4'd1: begin
                            q.pop_front();
                            q.pop_front();
                            q_size <= q_size - 2;
                        end
                        4'd2: begin
                            for (int i = 0; i < 9; i++) begin
                                q.pop_front();
                            end
                        end
                        4'd3: begin
                            myResult <= q.pop_front();
                            q_size <= q_size - 1;
                        end
                        4'd4: begin
                            myResult <= q.pop_front();
                        end
                        4'd5: begin
                            myResult = q.pop_front();
                            for (int i = 0; i < q_size-1; i++) q.pop_front();
                            q_size <= 0;
                        end
                    endcase
                end
                default: begin
                    q_size <= 0;
                end
            endcase
        end
    end

    ////////////////
    // Test tasks // 
    ////////////////

    // Tests if two swaps change the stack and if they
    // result in the correct arrangement of elements on the
    // stack
    task checkSwap;
        inData <= {4'h1, 16'h1}; // start
        @(posedge ck);
        inData <= {4'h2, 16'h1}; // enter
        @(posedge ck);
        inData <= {4'h4, 16'h8}; // swap
        @(posedge ck);
        inData <= {4'h4, 16'h8}; // swap
        @(posedge ck);
        inData <= {4'h4, 16'h1}; // add
        @(posedge ck);
        doneBehavior <= 5; 
        inData <= {4'h8, 16'h1}; // done
        @(posedge ck);
        inData <= {4'h0, 16'h0};
        @(posedge ck);
    endtask: checkSwap

    // Send random ops and payloads on the data lines a random
    // number of times
    task randomSequence;
        doneBehavior <= 4'd5;
        riters.randomize();
        for (int i = 0; i < riters.numIters; i++) begin
            rall.randomize();
            inData <= {rall.op, rall.payload};
            @(posedge ck); 
        end
    endtask: randomSequence

    // Check the edge cases of arithmetic overflow (addition and subtraction
    // with the intmin and intmax
    task overflowEdge;
        inData <= {4'h1, 16'h8000}; // start
        @(posedge ck);
        inData <= {4'h2, 16'h8000}; // enter
        @(posedge ck);
        inData <= {4'h4, 16'h1}; // add
        @(posedge ck);
        doneBehavior <= 4'd3;
        inData <= {4'h8, 16'h1}; // done
        @(posedge ck);
        inData <= {4'h0, 16'd0}; // clear the inData line
        @(posedge ck);

        inData <= {4'h1, 16'h7fff}; // start
        @(posedge ck);
        inData <= {4'h2, 16'h7fff}; // enter
        @(posedge ck);
        inData <= {4'h4, 16'h1}; // add
        @(posedge ck);
        doneBehavior <= 4'd3;
        inData <= {4'h8, 16'h1}; // done
        @(posedge ck);
        inData <= {4'h0, 16'd0}; // clear the inData line
        @(posedge ck);

        inData <= {4'h1, 16'h7fff}; // start
        @(posedge ck);
        inData <= {4'h2, 16'h8000}; // enter
        @(posedge ck);
        inData <= {4'h4, 16'h2}; // subtract
        @(posedge ck);
        doneBehavior <= 4'd3;
        inData <= {4'h8, 16'h1}; // done
        @(posedge ck);
        inData <= {4'h0, 16'd0}; // clear the inData line
        @(posedge ck);

        inData <= {4'h1, 16'h8000}; // start
        @(posedge ck);
        inData <= {4'h2, 16'h7fff}; // enter
        @(posedge ck);
        inData <= {4'h4, 16'h2}; // subtract
        @(posedge ck);
        doneBehavior <= 4'd3;
        inData <= {4'h8, 16'h1}; // done
        @(posedge ck);
        inData <= {4'h0, 16'd0}; // clear the inData line
        @(posedge ck);
    endtask: overflowEdge

    // Sends inputs on the data line after a data but before a start
    // to see if the inputs after the done are ignored
    task ignoreInputs;
        @(posedge ck);
        inData <= {4'h1, 16'd1}; // start
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // enter
        @(posedge ck);
        inData <= {4'h4, 16'h1}; // add
        @(posedge ck);
        doneBehavior <= 4'd3;
        inData <= {4'h8, 16'h1}; // done
        @(posedge ck);
        inData <= {4'h0, 16'd0}; // clear the inData line
        @(posedge ck);
        inData <= {4'h2, 16'd2}; // enter
        @(posedge ck);
        inData <= {4'h2, 16'd2}; // enter
        @(posedge ck);
        inData <= {4'h4, 16'h1}; // add
        @(posedge ck);
        doneBehavior <= 4'd3;
        inData <= {4'h8, 16'h1}; // done
        @(posedge ck);
        inData <= {4'h0, 16'd0}; // clear the inData line
        @(posedge ck);
    endtask: ignoreInputs

    // Causes the stack size to be 0 in between a start and done
    // to see if a protocol error is asserted 
    task emptyTheStack;
        inData <= {4'h1, 16'h10}; // enter
        @(posedge ck);
        inData <= {4'h4, 16'h20}; // pop
        @(posedge ck);
        inData <= {4'h2, 16'h15}; // enter
        @(posedge ck);
        doneBehavior <= 4'd3;    
        inData <= {4'h8, 16'h1};  // done
        @(posedge ck);
        inData <= {4'h0, 16'h0};
        @(posedge ck);
    endtask: emptyTheStack

    // Sends a done in a flagrantly wrong place
    task createUnexpectedDone;
        inData <= {4'h1, 16'h10}; // start
        @(posedge ck);
        inData <= {4'h2, 16'h15}; // enter
        @(posedge ck);
        doneBehavior <= 4'd4;
        inData <= {4'h8, 16'h1};  // done
        @(posedge ck);
        inData <= {4'h0, 16'h0};
        @(posedge ck);
    endtask: createUnexpectedDone

    // Sends an payload value with arithOp that is not one of the
    // specified operations
    task sendInvalidOp;
        inData <= {4'h1, 16'h11};
        @(posedge ck);
        inData <= {4'h2, 16'h1}; 
        @(posedge ck);
        inData <= {4'h4, 16'h15}; // invalid operation 
        @(posedge ck);
        doneBehavior <= 4'd2;
        inData <= {4'h8, 16'h1};
        @(posedge ck);
        inData <= {4'h0, 16'h0};
        @(posedge ck);
    endtask: sendInvalidOp

    // Sends an command that is not one of the specified ones
    task sendInvalidCmd;
        inData <= {4'h1, 16'h11};
        @(posedge ck);
        inData <= {4'h7, 16'h1}; // invalid command
        @(posedge ck);
        doneBehavior <= 4'd3;
        inData <= {4'h8, 16'h1};
        @(posedge ck);
        inData <= {4'h0, 16'h0};
        @(posedge ck);
    endtask: sendInvalidCmd

    // Adds and subtracts values to make overflow
    task makeOverflow;
        // overflow with addition
        inData <= {4'h1, 16'h7fff};
        @(posedge ck);
        inData <= {4'h2, 16'h5};
        @(posedge ck);
        inData <= {4'h4, 16'h1};
        @(posedge ck);
        doneBehavior <= 4'd3;
        inData <= {4'h8, 16'h1};
        @(posedge ck);
        inData <= {4'h0, 16'h0};
        @(posedge ck);
        // underflow with addition
        inData <= {4'h1, 16'h8000};
        @(posedge ck);
        inData <= {4'h2, 16'hffff};
        @(posedge ck);
        inData <= {4'h4, 16'h1};
        @(posedge ck);
        doneBehavior <= 4'd3;
        inData <= {4'h8, 16'h1};
        @(posedge ck);
        inData <= {4'h0, 16'h0};
        @(posedge ck);
        // overflow with subtraction
        inData <= {4'h1, 16'h800f};
        @(posedge ck);
        inData <= {4'h2, 16'h7fff};
        @(posedge ck);
        inData <= {4'h4, 16'h2};
        @(posedge ck);
        doneBehavior <= 4'd3;
        inData <= {4'h8, 16'h1};
        @(posedge ck);
        inData <= {4'h0, 16'h0};
        @(posedge ck);
        // underflow with subtraction
        inData <= {4'h1, 16'h0001};
        @(posedge ck);
        inData <= {4'h2, 16'h8000};
        @(posedge ck);
        inData <= {4'h4, 16'h2};
        @(posedge ck);
        doneBehavior <= 4'd3;
        inData <= {4'h8, 16'h1};
        @(posedge ck);
        inData <= {4'h0, 16'h0};
        @(posedge ck);
    endtask: makeOverflow

    // Sends a start then another start to see if the calculator
    // asserts protocolError
    task unexpectedStart;
        inData <= {4'h1, 16'd5}; // start
        @(posedge ck);
        inData <= {4'h1, 16'd5}; // start
        @(posedge ck);
        doneBehavior <= 4'd1;
        inData <= {4'h8, 16'h1}; // done
        @(posedge ck);
        inData <= {4'h0, 16'd0}; // clear the inData line
        @(posedge ck);
    endtask: unexpectedStart

    // Tries to add with there is only one element on the stack to
    // force a protocol error
    task addOneElem;
        inData <= {4'h1, 16'd5}; // start
        @(posedge ck);
        inData <= {4'h4, 16'h1}; // add
        @(posedge ck);
        doneBehavior <= 4'd4;
        inData <= {4'h8, 16'h1}; // done
        @(posedge ck);
        inData <= {4'h0, 16'd0}; // clear the inData line
        @(posedge ck);
    endtask: addOneElem

    // Tries to pop when there are no elements on the stack
    task pop_no_elems;
        inData <= {4'h1, 16'd1};
        @(posedge ck);
        inData <= {4'h4, 16'h20};
        @(posedge ck);
        inData <= {4'h4, 16'h20}; // pop when nothing to pop
        @(posedge ck);
        doneBehavior <= 4'd4;
        inData <= {4'h8, 16'h0001}; // done
        @(posedge ck);
        inData <= {4'h0, 16'd0}; // clear the inData line
        @(posedge ck);
    endtask: pop_no_elems
    
    // Sees whether each element in the stack can be written properly
    task addAllElems;
        inData <= {4'h1, 16'd1}; // 1
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 2
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 3
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 4
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 5
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 6
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 7
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 8
        @(posedge ck);
        inData <= {4'h4, 16'd1}; // 7
        @(posedge ck);
        inData <= {4'h4, 16'd1}; // 6
        @(posedge ck);
        inData <= {4'h4, 16'd1}; // 5
        @(posedge ck);
        inData <= {4'h4, 16'd1}; // 4 
        @(posedge ck);
        inData <= {4'h4, 16'd1}; // 3 
        @(posedge ck);
        inData <= {4'h4, 16'd1}; // 2 
        @(posedge ck);
        inData <= {4'h4, 16'd1}; // 1 
        @(posedge ck);
        doneBehavior <= 4'd3;
        inData <= {4'h8, 16'h0001}; // done
        @(posedge ck);
        inData <= {4'h0, 16'd0}; // clear the inData line
        @(posedge ck);
    endtask: addAllElems

    // Pushes 9 elements onto the stack to force a stackOverflow
    task overflowStack;
        inData <= {4'h1, 16'd1}; // 1
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 2
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 3
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 4
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 5
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 6
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 7
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 8
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 9
        @(posedge ck);
        doneBehavior <= 4'd2;
        inData <= {4'h8, 16'h0001}; // done
        @(posedge ck);
        inData <= {4'h0, 16'd0}; // clear the inData line
        @(posedge ck);
    endtask: overflowStack

    // Sends in a 0000 and performs operations on it to get to ffff,
    // checking whether any of the result bits are stuck at 0
    task stuckAt0;
        inData <= {4'h1, 16'd0}; // start
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 1 
        @(posedge ck);
        inData <= {4'h4, 16'h1}; // add
        @(posedge ck);
        inData <= {4'h4, 16'h10}; // negate
        @(posedge ck);
        doneBehavior <= 4'd3;
        inData <= {4'h8, 16'h0001}; // done
        @(posedge ck);
        inData <= {4'h0, 16'd0}; // clear the inData line
        @(posedge ck);
    endtask: stuckAt0

    // Sends in a ffff and performs operations on it to get to 0000,
    // checking whether any of the result bits are stuck at 1
    task stuckAt1;
        inData <= {4'h1, 16'hffff}; // start
        @(posedge ck);
        inData <= {4'h2, 16'd1}; // 1 
        @(posedge ck);
        inData <= {4'h4, 16'h1}; // add
        @(posedge ck);
        doneBehavior <= 4'd3;
        inData <= {4'h8, 16'h0001}; // done
        @(posedge ck);
        inData <= {4'h0, 16'd0}; // clear the inData line
        @(posedge ck);
    endtask: stuckAt1

    // Performs a random operation on two random numbers
    task simpleRandOper;
        if (!r2op.randomize()) begin
            $display("Bad random numbers! A: %d B: %d, op: %d",
                      r2op.A, r2op.B, r2op.op);
        end 
        else begin
            inData <= {4'h1, r2op.A}; // start
            @(posedge ck);
            inData <= {4'h2, r2op.B}; // enter
            @(posedge ck);
            inData <= {4'h4, r2op.op}; // random operation
            @(posedge ck);
            if (r2op.op == 16'h10 || r2op.op == 16'h8) randomOperation();
            doneBehavior <= 4'd3;
            inData <= {4'h8, 16'h1}; // done
            @(posedge ck);
            inData <= {4'h0, 16'd0}; // clear the inData line
            @(posedge ck);
        end
    endtask: simpleRandOper

    // Performs a single random operation
    task randomOperation;
        if (!rop.randomize()) begin
            $display("Bad random number! op: %d", rop.op);
        end 
        else begin
            inData <= {4'h4, rop.op}; // arithOp
            @(posedge ck);
        end
    endtask: randomOperation

    // Negates an element on the stack to check if it is negated properly
    task simpleNegate;
        if (!r2op.randomize()) begin
            $display("Bad random number! A: %d", r2op.A);
        end
        else begin
            inData <= {4'h1, r2op.A}; // start
            @(posedge ck);
            inData <= {4'h4, 16'h10}; // negate
            @(posedge ck);
            inData <= {4'h8, 16'h0001}; // done
            doneBehavior <= 4'd3;
            @(posedge ck);
            inData <= {4'h0, 16'd0}; // clear the inData line
            @(posedge ck);
        end
    endtask: simpleNegate

    // Adds two random numbers with the possiblity of overflow
    task simpleAdd;
        if (!rvals.randomize()) begin
            $display("Bad random numbers! A: %d B: %d",
                      rvals.payloadA, rvals.payloadB);
        end
        else begin
            @(posedge ck);
            inData <= {4'h1, rvals.payloadA}; // start
            @(posedge ck);
            inData <= {4'h2, rvals.payloadB}; // enter
            @(posedge ck);
            inData <= {4'h4, 16'h1}; // add
            @(posedge ck);
            doneBehavior <= 4'd3;
            inData <= {4'h8, 16'h1}; // done
            @(posedge ck);
            inData <= {4'h0, 16'd0}; // clear the inData line
            @(posedge ck);
        end
    endtask: simpleAdd 
    
    // Adds two random numbers that won't overflow
    task simpleAddNoOverflow;
        if (!noOver.randomize()) begin
            $display("Bad random numbers! A: %d B: %d",
                      noOver.payloadA, noOver.payloadB);
        end
        else begin
            inData <= {4'h1, noOver.payloadA}; // start
            @(posedge ck);
            inData <= {4'h2, noOver.payloadB}; //enter
            @(posedge ck);
            inData <= {4'h4, 16'h1}; //add
            @(posedge ck);
            inData <= {4'h8, 16'h1}; //done
            doneBehavior <= 4'd3;
            @(posedge ck);
            inData <= {4'h0, 16'd0}; // clear the inData line
            @(posedge ck);
        end
    endtask: simpleAddNoOverflow 

    ////////////////
    // Assertions //
    ////////////////

    // These assertions run concurrently with the testbench and continuously
    // checked the following properties.

    // Check the various conditions that constitute acceptable behavior after a
    // calculation is finished. This is primarily that the result is correct or 
    // if not the errors are asserted.
    property result_corr_prop();
        @(posedge ck) disable iff (~rst_l)
                      first_match ((data.op == start) ##[1:$] (data.op == done)) |->
                                  ((finished & 
                                    correct  & 
                                    result == myResult &
                                    ~stackOverflow     &
                                    ~unexpectedDone    &
                                    ~dataOverflow      &
                                    ~protocolError) 
                                   or
                                   (finished & 
                                    ~correct &
                                    (stackOverflow  | 
                                     unexpectedDone | 
                                     dataOverflow   |
                                     protocolError)) 
                                   or
                                  (unexpectedDone & 
                                   (q_size != 1)));
    endproperty: result_corr_prop
                                               
    result_corr: assert property(result_corr_prop())
        else $error("\n%m Done behavior not correct!\n \
                 Input:\n \
                     op: %h \n \
                     data: %h\n \
                 Outputs:\n \
                     myResult: %h \n \
                     result: %h \n \
                     SO: %b\n \
                     UD: %b\n \
                     DO: %b\n \
                     PE: %b\n \
                     correct: %b\n \
                     finished: %b\n \
                     stack size: %d\n",
                     $past(data, 1), $sampled(data), $sampled(myResult), $sampled(result), 
                     $sampled(stackOverflow), $sampled(unexpectedDone),
                     $sampled(dataOverflow), $sampled(protocolError), 
                     $sampled(correct), $sampled(finished), $sampled(q_size));

    // Checks that if a stackOverflow is asserted it was asserted under the correct
    // circumstances
    property stack_over_prop();
        @(posedge ck) disable iff (~rst_l) 
                      stackOverflow |-> (q_size > 8);
    endproperty: stack_over_prop

    stack_over: assert property(stack_over_prop())
        else $error("\n%m stackOverflow incorrectly asserted!\n \
                    stackOverflow: %b\n \
                    stack size: %d\n",
                    $sampled(stackOverflow), $sampled(q_size));

    // Makes sure a stackOverflow is asserted when it should
    property over_asserted_prop();
        @(posedge ck) disable iff (~rst_l)
                      (q_size > 8) |-> stackOverflow;
    endproperty: over_asserted_prop

    over_asserted: assert property(over_asserted_prop())
        else $error("\n%m stackOverflow not asserted when it should have!\n \
                    stackOverflow: %b\n \
                    stack size: %d\n",
                    $sampled(stackOverflow), $sampled(q_size));
    
    // An unexpected done only occurs when the stack size > 1
    property undone_prop();
        @(posedge ck) disable iff (~rst_l)
                      unexpectedDone |-> (q_size > 1);
    endproperty: undone_prop 

    undone: assert property(undone_prop())
        else $error("\n%m unexpectedDone incorrectly asserted!\n \
                     UD: %b\n \
                     stack size: %d\n", 
                     $sampled(unexpectedDone), $sampled(q_size));

    // Unexpected done is asserted when an done occurs out of place
    property unexpect_done_prop();
        @(posedge ck) disable iff (~rst_l)
                      (data.op == done && 
                       q_size > 1      &&
                       ~protocolError  &&
                       ~dataOverflow   &&
                       ~stackOverflow) |-> 
                      unexpectedDone;
    endproperty: unexpect_done_prop

    unexpect_done: assert property(unexpect_done_prop())
        else $display("\n%m No unexpected done when done asserted too early!\n");
    
    // If there is overflow, dataOverflow must be asserted
    property data_over_prop();
        @(posedge ck) disable iff (~rst_l) 
                      overflow |-> dataOverflow;
    endproperty: data_over_prop

    data_over: assert property(data_over_prop())
        else $display("\n%m Arithmetic overflow while adding two positives!");

    // If an operation occurs with insufficient elements on the stack an error 
    // should be asserted
    property insuf_elems_prop();
        @(posedge ck) disable iff (~rst_l)
                      (data.op == arithOp && 
                       (((data.payload == 16'h1  || 
                          data.payload == 16'h2  || 
                          data.payload == 16'h4  ||
                          data.payload == 16'h8) && 
                          q_size < 1)            ||
                       ((data.payload == 16'h10  ||
                         data.payload == 16'h20) && 
                         q_size == 0)))          |-> 
                       protocolError ##1 (protocolError, cprot.sample());
    endproperty: insuf_elems_prop

    insuf_elems: assert property(insuf_elems_prop())
        else $display("\n%m Insufficient elements and no p_error asserted!");

    // A protocolError is asserted if a start...start occurs
    property unexpect_start_prop();
        @(posedge ck) disable iff (~rst_l)
                      ((data.op == start) ##1 (data.op != done && data.op != start)[*0:$]
                      ##1 data.op == start) |-> (protocolError, cprot.sample()); 
    endproperty: unexpect_start_prop

    unexpect_start: assert property(unexpect_start_prop())
        else $display("\n%m A start-start not caught!\n");
        
    // A protocol error is asserted if the stack is empty between a start and done
    property empty_stack_prop();
        @(posedge ck) disable iff (~rst_l)
                      ((data.op == start) ##1 ((data.op != done) && (q_size < 32'd1))[*1:$]) 
                      |-> (protocolError, cprot.sample()); 
    endproperty: empty_stack_prop

    empty_stack: assert property(empty_stack_prop())
        else $display("\n%m Stack is empty and no protocol error!\n");

    // A command outside the specified commands is given
    property invalid_cmd_prop();
        @(posedge ck) disable iff (~rst_l)
                      ((data.op == start) ##1
                       (data.op != start   && 
                        data.op != enter   &&
                        data.op != arithOp &&
                        data.op != done    &&
                        data.op != 4'd0))  |-> 
                        (protocolError, cprot.sample()); 
    endproperty: invalid_cmd_prop

    invalid_cmd: assert property(invalid_cmd_prop())
        else $display("\n%m Invalid command and no protocol error!\n");

    // An invalid operation is given to the calculator
    property invalid_op_prop();
        @(posedge ck) disable iff (~rst_l)
                       (data.op == start)      |-> 
                       (data.op == start)      ##1
                      ((data.op == arithOp)    && 
                       (data.payload != 16'h1  &&
                        data.payload != 16'h2  &&
                        data.payload != 16'h4  &&
                        data.payload != 16'h8  &&
                        data.payload != 16'h10 &&
                        data.payload != 16'h20))[*1:$] |-> protocolError;
    endproperty: invalid_op_prop

    invalid_op: assert property(invalid_op_prop())
        else $display("\n%m Invalid operation and no protocol error!\n");

    // Ensures that inputs are ignore between done...start
    property ignore_input_prop();
        @(posedge ck) disable iff (~rst_l)
                       (data.op == done)         |-> 
                       (data.op == done)         ##1 
                      ((data.op != start)        && 
                       (!$changed(result))       && 
                       (!$rose(stackOverflow))   &&
                       (!$rose(unexpectedDone))  &&
                       (!$rose(dataOverflow))    &&
                       (!$rose(protocolError))   &&
                       (!$rose(correct))         &&
                       (!$rose(finished)))[*0:$] ##1 
                       (data.op == start);
    endproperty: ignore_input_prop

    ignore_input: assert property(ignore_input_prop())
        else $display("\n%m Inputs not ignored. Activity after done!\n");

    // Checks that swaps do not reduce the stack size
    property no_swap_reduce_prop();
        @(posedge ck) ((data.op == start)  ##1 (data.op == enter)       ##1
                       (data.op == arithOp &&   data.payload == 16'h8)  ##1
                       (data.op == arithOp &&   data.payload == 16'h8)) |-> 
                       (~protocolError, cprot.sample());
    endproperty: no_swap_reduce_prop

    no_swap_reduce: assert property(no_swap_reduce_prop())
        else $display("\n%m Two swaps caused a protocol error\n");

endmodule: top
