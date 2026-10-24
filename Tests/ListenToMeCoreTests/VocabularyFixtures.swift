/// Classifier fixtures (issue #222): one realistic transcript per preset, and conversations that only
/// touch a domain casually or are ordinary meetings, which must never trigger a suggestion.
/// All text is written for these tests; no real people or copyrighted material.
enum VocabularyFixtures {
    static let positives: [String: String] = [
        "medical": """
        okay so this is a sixty eight year old woman with a history of atrial fibrillation and heart failure \
        who came in with worsening dyspnea over the last week, she says she can't lie flat anymore and has \
        been sleeping in a recliner. she's on apixaban five milligrams BID, metoprolol twenty five twice a \
        day, and furosemide forty by mouth daily. on exam she has pitting edema up to the knees, crackles at \
        both bases, and her neck veins look full. her oxygen was ninety one percent so we started two liters. \
        troponin was flat times two, BNP is elevated at around eleven hundred, and her creatinine bumped from \
        one point one to one point six, so i'm a little worried about her kidneys. can we get an \
        echocardiogram today, her last ejection fraction was thirty five percent about a year ago. right, and \
        i'd hold off on adding anything new for her blood pressure until we see the kidney numbers trend. \
        agreed, let's switch the furosemide to forty IV twice a day, keep her on a fluid restriction, strict \
        ins and outs, daily weights, and recheck labs in the morning. does she have any allergies? none listed \
        in the chart. okay, i'll talk to her daughter this afternoon and update the family on the plan.
        """,
        "legal": """
        okay so on the facts, the plaintiff signed the services contract in march and the defendant stopped \
        paying in august, which we think is a material breach. their answer raises force majeure as an \
        affirmative defense, but the clause only covers natural disasters and government orders, not a supply \
        shortage. i'd like to get the interrogatories out by friday so we have their answers before the \
        deposition of the cfo. one more thing, they filed a motion to dismiss for lack of personal \
        jurisdiction and our opposition is due in fourteen days, so can the paralegal pull the shipping \
        records showing they sold into the state. also look at the indemnification section, if it covers \
        attorney's fees we should plead it now rather than later. on damages, the contract has a liquidated \
        damages clause, so let's not overreach in the demand letter. and remind me about the statute of \
        limitations on the fraud count, i think we're fine but i want it on the calendar. if the documents \
        come back the way we expect, we move for summary judgment in the spring, otherwise we start talking \
        settlement numbers with the other side.
        """,
        "finance": """
        alright, let's start with the quarter. ARR closed at forty two million, up about thirty one percent on \
        last year, and retention held up well. gross margin dipped ninety basis points because the hosting \
        spend moved into COGS earlier than we planned. adjusted EBITDA is positive once you strip out the \
        one-time legal charge. DSO crept up to sixty one days, mostly two enterprise customers paying late, so \
        the treasury team is going to chase those this week. for the board deck, the DCF is using a WACC of \
        eleven percent and long-term growth of three, and honestly the valuation is really sensitive to both, \
        so i'd like a sensitivity table right next to it. FP&A wants to reforecast every quarter instead of \
        locking the annual plan, which i support. one thing to flag, the convertible note converts at the next \
        priced round, so we need the cap table updated before we talk to any investors. also audit fieldwork \
        starts in three weeks and they will definitely ask about deferred revenue on the multi-year contracts, \
        so let's have the ASC 606 memo ready before they arrive.
        """,
        "software-cloud": """
        okay so quick recap of last night's incident. the checkout service started throwing 5xx errors around \
        eleven and pagerduty paged whoever was on-call within about two minutes. we traced it to the canary \
        deployment that went out through github actions, the new build had a database connection limit that \
        was way too low so postgres started refusing connections under load. we did a rollback around eleven \
        forty and the error budget for the month took a pretty big hit, we burned something like forty percent \
        of it. the pods themselves looked fine, but the startup probe kept passing even though the service \
        couldn't reach the database, so the load balancer kept sending it traffic. action item one is to fix \
        that probe so it actually checks the database. second, i want the redis cache warmed before we shift \
        any traffic, and third we should add a monitor on p99 latency for that endpoint. can someone own the \
        postmortem and get it written up by thursday. also open question, do we keep the canary at five \
        percent or drop it to one percent for anything that touches the billing path. i'd lean one percent, \
        but let's decide on friday.
        """,
        "engineering": """
        alright, on the bracket redesign, the fea came back and the von mises stress at the inside corner is \
        about eighty percent of yield strength for the aluminum 6061, so the factor of safety is too thin once \
        you add the vibration loads. i'd like to add a bigger radius there and bump the wall to four \
        millimeters. the machine shop says that is fine, it adds maybe two minutes per part. on the drawing, \
        the tolerance stack-up between the two bolt holes doesn't close. we're calling out true position of \
        point one millimeter but the mating part is only held to point two five, so either we tighten the gd&t \
        callout or we slot one of the holes. also the torque spec on the m8 fasteners should be twenty five \
        newton-meters, not thirty, otherwise the coating is going to crack. the supplier wants the updated bom \
        by friday so they can requote. risk wise, the dvt build slips a week if the new revision isn't \
        released by the twentieth, and we still haven't seen any data on the coated version. let's run an fmea \
        on the mounting interface before the next gate, and i'll send out the updated drawing tonight.
        """,
        "sales": """
        okay so quick recap from the discovery call last week, their economic buyer is the cfo and our main \
        contact is the head of operations, they're comparing us against salesforce and one other vendor, and \
        the real deadline is their current contract running out in march. on pricing they pushed back on the \
        per-seat pricing, so i floated a multi-year discount with a ramp deal, smaller seat count in year one \
        and then more seats in year two. what did legal say about the msa. they sent redlines yesterday, \
        mostly the liability language and the renewal terms, nothing crazy, and the security questionnaire is \
        with our team, it should be back by friday. can we get the order form drafted before then. yes, i'll \
        get finance to approve the discount today. how are we tracking for the quarter, is this in the commit \
        forecast or still best case. i'd put it in commit, we have a mutual action plan with dates on it and \
        the cfo already signed off on the numbers. okay great, log everything in hubspot and let's book a \
        follow up with their procurement people for tuesday.
        """,
        "education-research": """
        okay so for the methods chapter your committee is going to ask how you handled the likert scale items, \
        did you check cronbach's alpha. yes, it came out at point eight one, so internal consistency looks \
        fine. good, and then for the main analysis you ran an anova across the three conditions. right, and \
        the p-value for the interaction was point zero three, but i still need to run the post hoc comparisons \
        with a bonferroni correction. also report the effect size, reviewers always ask for it. what about the \
        control group, we lost a few participants after the second session. mention the attrition in the \
        write-up and note it in the amendment, you'll need irb approval for the follow-up survey anyway. okay. \
        and for the literature review, i found two preprints on arxiv that basically replicate our pilot. cite \
        them, but flag that they haven't been published yet. timeline wise your thesis defense is in april, so \
        i'd like a full draft by the end of february, and remember you're still teaching the stats lab on \
        thursdays, so plan your weeks around that.
        """
    ]

    /// Everyday conversations that brush against a domain, and ordinary meetings with no domain at all.
    static let negatives: [String] = [
        // A doctor's appointment, chatted about between friends.
        """
        so how did your appointment go yesterday? honestly it was fine, mostly a lot of sitting in the waiting \
        room. the doctor said my blood pressure was a little high but she thinks it's because i had just run \
        up three flights of stairs since the elevator was broken again. she wants me to cut back on salt and \
        come back in a few months. that's not too bad. did you ask about your knee? yeah, she said it's \
        probably just from running on pavement and told me to ice it and take it easy for a couple of weeks. \
        if it still bothers me she'll send me for an MRI, but i really hope it doesn't come to that because my \
        insurance is terrible. ugh, tell me about it, i spent forty minutes on the phone with mine last week \
        over a bill for a flu shot. anyway, do you still want to grab lunch on thursday? sure, there's that \
        new ramen place next to the pharmacy on main street. perfect, i'll text you after work and we can \
        figure out a time. sounds good, and go easy on that knee.
        """,
        // Jury duty and a lease, at home.
        """
        so my cousin finally got called for jury duty and she's annoyed because it's the same week as her \
        trip. she asked if she could push it back and they said yes, but only once. honestly i kind of want to \
        go, it sounds interesting, like a real courtroom drama. did you ever watch that show about the lawyers \
        in chicago? my mom loved it. anyway, the landlord sent us a new lease yesterday and the rent is going \
        up again, like eighty dollars a month. dad read the whole thing at the kitchen table with his glasses \
        on and said there's nothing weird in it, just the usual stuff about pets and parking. i still think we \
        should ask if we can paint the bedroom. oh and grandma finally signed the power of attorney papers so \
        dad can handle her bills, which is a relief. and remember the guy next door who backed into our fence \
        with his truck? his insurance finally paid, so we don't have to deal with that anymore. okay, should \
        we order pizza or go to the taco place tonight, i'm starving.
        """,
        // Household money.
        """
        did you see how much the groceries were this week? i swear eggs doubled again. anyway my sister got \
        that new job at the startup and she keeps talking about her stock options like she's going to retire \
        at thirty, i told her to just enjoy the salary. we're trying to save up for the trip to portugal in \
        the spring, so no more takeout on weekdays, that's the rule now. my dad keeps telling me to put a \
        little into an index fund every month and forget about it, which is probably good advice, but i'd \
        rather pay off the car first. oh, and the bank charged me a fee for going under the minimum balance, \
        which was so annoying, i called and they took it off. we should split the electric bill differently \
        since you're working from home more now, maybe sixty forty? also remind me to pay you back for the \
        concert tickets, i keep forgetting. are you coming to the barbecue on saturday? bring the folding \
        chairs if you can, we never have enough.
        """,
        // A lost phone and a tech outage, over dinner plans.
        """
        did you ever get your photos back after the phone died? yeah mostly, my brother set up some cloud \
        backup thing for me last year so almost everything was there, except the videos from the beach trip, \
        which is annoying. honestly i don't trust any of that stuff, my laptop keeps nagging me to install an \
        update and every time i do something stops working. last week the printer just vanished from the list. \
        my niece works at one of those tech companies downtown, she says the whole office went down for a day \
        because some website they all depend on had an outage, and nobody could even log in to check their \
        email. she said they had to turn on two-factor authentication for everything afterwards, so now she \
        gets a text code every time she opens her laptop. i'd lose my mind. anyway are we still doing dinner \
        saturday? i found a place near the river that does the good dumplings, and they finally take \
        reservations online, so i can book it tonight if you're in. sure, seven works, i'll ask if my sister \
        wants to come too.
        """,
        // A deck repair at home.
        """
        so the guy came by to look at the deck again, he thinks the whole thing needs to come down, the posts \
        are rotting at the bottom. how much is that going to cost? he didn't give a number yet, he said he'd \
        send something next week after he checks with the city about a permit. honestly i just want it done \
        before summer, the kids keep asking when they can have friends over for a barbecue. did he say \
        anything about the air conditioning? yeah, he said the unit is old but it should last another year or \
        two, and when we replace it we should get one of the quieter ones. my dad used to fix everything \
        himself, he had a whole workbench in the garage with every tool you can imagine, a drill press, \
        clamps, those little measuring calipers he loved. i still have his toolbox. maybe we could build the \
        new planter boxes ourselves this weekend, the kids would love it. sure, but i'm not climbing a ladder, \
        last time i nearly fell off. fine, i'll pick up the wood and screws on saturday morning and we'll see \
        how far we get.
        """,
        // Buying a car.
        """
        so how was the dealership, did you end up getting the car. not yet, the salesman kept trying to sell \
        me the extended warranty and the floor mats and i just wanted the price. classic, they always do that. \
        my brother in law worked at a dealership for a year and he said they make more on the extras than on \
        the car itself. did you negotiate at all. a little, i told him i had a better offer from the place \
        across town, which was sort of true, and he went to talk to his manager like three times. that's the \
        whole show, the manager thing. anyway he knocked off five hundred dollars and threw in free oil \
        changes for a year. not bad. i still have to think about the financing though, the interest rate \
        seemed high. you should check with your credit union first, they're usually cheaper. good idea, i'll \
        call them tomorrow. also my phone has been ringing nonstop with cold calling from some solar company, \
        i don't know how they got my number. just block them, that's what i do. anyway want to grab lunch \
        saturday.
        """,
        // Parent night at school.
        """
        how was parent night at the school. it was fine, packed though, we barely found parking. did you meet \
        the new teacher. yeah, she seems nice, very organized, she handed out a sheet with all the dates for \
        the year. is the homework any better than last year. a bit, she said about twenty minutes a night and \
        reading on weekends, and she even gives extra credit for keeping a reading log. that's reasonable. our \
        son keeps forgetting his backpack, so we'll see. ha, ours too, i swear half my mornings are spent \
        looking for shoes and lunch boxes. are you doing the science fair this year. we're thinking about it, \
        he wants to build a volcano again, i told him maybe something new. what about the field trip, did you \
        sign the form. not yet, it's to the aquarium in november and they need two more parent volunteers. i \
        might do it if work lets me off. also the pickup line has gotten ridiculous since they moved the gate. \
        tell me about it, i sat there fifteen minutes yesterday. we should carpool, it would save us both \
        time. good idea, let's figure it out this weekend.
        """,
        // An ordinary team meeting with no specialist vocabulary.
        """
        okay let's get started, thanks everyone for joining. first item is the offsite next month, we have the \
        venue booked for the thursday and friday, and we still need a headcount by the end of this week so \
        please reply to the email if you haven't. second, the new office hours for the front desk start on \
        monday, they'll be open from eight to six now instead of nine to five. third, we're going to try \
        moving this weekly meeting to tuesday mornings because so many people have conflicts on wednesdays, \
        let me know if that doesn't work for you. on the hiring side, we have two people starting in the next \
        couple of weeks, so if you're asked to help with onboarding please make some time to show them around \
        and introduce them to the team. there was a question about the parking situation, facilities says the \
        new spots behind the building will open in about three weeks. last thing, the holiday party committee \
        is looking for volunteers, it's a fun group and they meet once a week over lunch. anything else before \
        we wrap up? okay, thanks everyone, have a good rest of your week.
        """,
        // English and Chinese, mixed, about a weekend trip.
        """
        我们这个周末去哪里玩？ maybe we can drive to the lake, 天气预报说星期六会出太阳。 that sounds nice, 但是我还要先去超市买点东西， we are out \
        of rice and eggs again. 好的，那我们早上九点出发吧， i'll pack some sandwiches and fruit for the kids. 你记得带上防晒霜和帽子， \
        last time everyone got sunburned. 对了，我妈妈也想一起去， is there enough room in the car? 应该可以， if we fold the \
        back seat down and put the cooler in the trunk. 好，那我今天晚上给她打电话。 also we should check if the boat rental \
        is open this season, 去年他们好像关门了。 我上网查一下， and i'll book a table for lunch at the fish place near the \
        dock. 太好了，孩子们一定很开心。 let's not forget the fishing rods this time, 他们上次一直在说。 okay, i'll put them by the \
        door tonight so we don't forget in the morning.
        """
    ]
}
