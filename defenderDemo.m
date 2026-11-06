function outcome = defenderDemo(seed, show)
%DEFENDERDEMO  Tiny stand-alone demo: ONE defender vs ONE ball. Learning only.
%   defenderDemo          watch one run
%   defenderDemo(5)       watch a different random shot (seed 5)
%   defenderDemo(5,false) run without drawing, just return 'GOAL' or 'CLEARED'
%
%   Not part of the team simulator: plain MATLAB, no packages, no Stateflow.
%   Same idea as the real thing: every 0.05 s  LOOK -> DECIDE -> MOVE -> DRAW.
%
%   Defender states:
%     GUARD   stand between the ball and our goal, 1.8 m out from the goal
%     ATTACK  ball is close and in our half: run at it
%     CLEAR   kick the ball up the pitch; back to GUARD once the ball has gone
if nargin < 1, seed = 1; end
if nargin < 2, show = true; end
rng(seed);

% ---------- settings (SI units: m, s) ----------
dt         = 0.05;   % s, time per step (20 steps per second)
robotSpeed = 0.3;   % m/s, top walking speed
guardDist  = 1.8;    % m, how far in front of our goal the defender guards
attackDist = 1.0;    % m, run at the ball when it is closer than this
kickDist   = 0.25;   % m, close enough to kick
clearExitDist = kickDist + 0.3;   % m, leave CLEAR once the ball is this far (it has gone)
kickSpeed  = 2.5;    % m/s, ball speed after a clearance
friction   = 0.3;    % m/s^2, how fast the rolling ball slows down
goal       = [-4.5 0];   % our goal (left side), 2.6 m wide

% ---------- start: the "first page of the flipbook" ----------
defender = [-2.5 0];                          % defender position [x y]
ball     = [2 -2 + 4*rand];                   % ball somewhere in their half
aim      = [-4.5, -1 + 2*rand];               % shot aimed inside our goal
ballVel  = 2.0 * (aim - ball) / norm(aim - ball);   % 2 m/s towards the goal
state    = 'GUARD';
outcome  = 'SAVED';                           % if time runs out, ball stopped

for step = 1:600                              % at most 30 s
    % ===== 1. LOOK: what does the defender see? =====
    distToBall = norm(ball - defender);

    % ===== 2. DECIDE: state machine (this is what Stateflow will draw) =====
    switch state
        case 'GUARD'
            if distToBall < attackDist && ball(1) < 0
                state = 'ATTACK';
            end
        case 'ATTACK'
            if distToBall < kickDist
                state = 'CLEAR';
            elseif distToBall > attackDist + 0.5    % ball got away: give up
                state = 'GUARD';
            end
        case 'CLEAR'
            if distToBall > clearExitDist           % ball has gone: go back
                state = 'GUARD';
            end
    end

    % ===== 3. ACT: turn the state into a target (and maybe a kick) =====
    switch state
        case 'GUARD'
            towardBall = (ball - goal) / norm(ball - goal);   % direction goal -> ball
            target = goal + guardDist * towardBall;           % on that line
        case 'ATTACK'
            target = ball;
        case 'CLEAR'
            target = ball;                                    % stay on the ball
            if distToBall < kickDist                          % only kick if in reach
                ballVel = kickSpeed * [1 0.3*randn];          % kick upfield
                outcome = 'CLEARED';
            end
    end

    % ===== 4. MOVE the defender (never faster than robotSpeed) =====
    toTarget = target - defender;
    stepLen  = min(norm(toTarget), robotSpeed * dt);
    if norm(toTarget) > 0
        defender = defender + stepLen * toTarget / norm(toTarget);
    end

    % ===== 5. ROLL the ball (slows down because of friction) =====
    ball  = ball + ballVel * dt;
    speed = norm(ballVel);
    if speed > 0
        ballVel = ballVel * max(speed - friction * dt, 0) / speed;
    end

    % ===== 6. REFEREE =====
    if ball(1) <= -4.5
        if abs(ball(2)) < 1.3, outcome = 'GOAL'; end
        break
    end
    if strcmp(outcome, 'CLEARED') && ball(1) > 0, break; end   % safely away
    if norm(ballVel) == 0, break; end                         % ball stopped

    % ===== 7. DRAW this "page" =====
    if show
        drawPitch(defender, ball, state, step * dt);
    end
end

if show, title(sprintf('Result: %s', outcome)); end
fprintf('seed %d: %s\n', seed, outcome);
end

function drawPitch(defender, ball, state, t)
cla; hold on; axis equal; axis([-5 5 -3.5 3.5]);
rectangle('Position', [-4.5 -3 9 6], 'EdgeColor', [0 0.5 0]);   % pitch
plot([0 0], [-3 3], 'Color', [0 0.5 0]);                          % halfway line
plot([-4.5 -4.5], [-1.3 1.3], 'b', 'LineWidth', 4);               % OUR goal
plot(defender(1), defender(2), 'bo', 'MarkerSize', 14, 'MarkerFaceColor', 'b');
plot(ball(1), ball(2), 'o', 'MarkerSize', 7, 'MarkerFaceColor', [1 0.5 0], 'MarkerEdgeColor', 'k');
title(sprintf('t = %.1f s   state: %s', t, state));
drawnow;
end
