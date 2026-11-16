import SceneKit

enum RigChecks {
    @MainActor static func run(assets: Assets) throws {
        func close(_ a: Double, _ b: Double, _ message: String = "Native rig coordinate") {
            precondition(abs(a-b)<0.0001,message+": \(a), expected \(b)")
        }
        func reject(_ operation: () throws -> Void) {
            do {try operation(); preconditionFailure("Malformed rig input was accepted")}
            catch AssetError.model {} catch {preconditionFailure("Unexpected rig error: \(error)")}
        }
        func bone(_ model: SCNNode, _ name: String) -> SCNNode {
            var result: SCNNode?
            model.enumerateChildNodes { node,_ in if node.name?.lowercased() == name.lowercased() {result = node} }
            precondition(result != nil,"Missing native bone "+name)
            return result!
        }
        func height(_ node: SCNNode, in model: SCNNode) -> (Double,Double) {
            let bounds = node.geometry!.boundingBox
            let points: [SCNVector3] = [bounds.min.x,bounds.max.x].flatMap { x in [bounds.min.y,bounds.max.y].flatMap { y in
                [bounds.min.z,bounds.max.z].map {z in node.convertPosition(.init(x,y,z),to:model)}
            } }
            return (points.map {$0.y}.min()!,points.map {$0.y}.max()!)
        }
        let factory = Mobs(assets:assets), radians = Double.pi/180
        let polar = try factory.make(.polarBear), cub = try factory.make(.polarBear,baby:true)
        close(bone(polar,"body").eulerAngles.x,-Double.pi/2,"Adult polar torso retains its native bind")
        close(bone(cub,"body").eulerAngles.x,0,"Cub torso is already horizontal")
        let torso = height(bone(polar,"body"),in:polar)
        close(torso.0,8.0/16); close(torso.1,19.0/16)
        close(polar.boundingBox.min.y,0); close(cub.boundingBox.min.y,0)
        close(polar.scale.x,1.2); close(cub.scale.x,1)
        let adultMotion = try factory.locomotion(.polarBear), cubMotion = try factory.locomotion(.polarBear,baby:true)
        close(adultMotion.width,1.4); close(cubMotion.width,0.7)

        let wolf = try factory.make(.wolf), pup = try factory.make(.wolf,baby:true)
        close(bone(wolf,"body").eulerAngles.x,-Double.pi/2)
        close(bone(wolf,"upperbody").eulerAngles.x,-Double.pi/2)
        close(bone(wolf,"upperbody").position.z,-3.0/16)
        close(bone(wolf,"leg0").position.y,8.0/16)
        close(bone(pup,"body").eulerAngles.x,0,"Pup excludes adult setup")
        let parrot = try factory.make(.parrot)
        close(bone(parrot,"leg0").position.y,-6.0/16)
        close(bone(parrot,"leg0").eulerAngles.x,16.713*radians)
        close(bone(parrot,"wing0").position.x,1.5/16)
        for species in [Species.guardian,.elderGuardian] {
            let model = try factory.make(species)
            close(bone(model,"spikepart0").eulerAngles.x,45*radians)
            close(bone(model,"spikepart4").eulerAngles.x,-90*radians)
            close(bone(model,"spikepart4").eulerAngles.y,45*radians)
            close(bone(model,"spikepart0").position.y,(24-8*1.56)/16)
            close(bone(model,"tailpart1").position.y,-0.5/16)
            close(bone(model,"tailpart1").position.z,14.0/16)
            close(bone(model,"tailpart2").position.z,6.0/16)
            close(bone(model,"eye").position.y,24.0/16)
            close(bone(model,"eye").position.z,-8.25/16)
        }
        for species in [Species.witch,.evoker] {
            let model = try factory.make(species), arms = bone(model,"arms")
            close(arms.eulerAngles.x,42.97*radians)
            let joint = arms.convertPosition(SCNVector3Zero,to:model)
            close(joint.y,21.0/16); close(joint.z,-1.0/16)
            if species == .evoker {precondition(bone(model,"leftarm").isHidden && bone(model,"rightarm").isHidden)}
        }
        let turtle = try factory.make(.turtle)
        close(bone(turtle,"body").eulerAngles.x,-Double.pi/2,"Animated zero must preserve the shell bind")
        precondition(bone(turtle,"eggbelly").isHidden,"Calm turtles exclude pregnancy geometry")

        for baby in [false,true] {
            let rabbit = try factory.make(.rabbit,baby:baby), head = bone(rabbit,"head")
            let rig = try factory.rig(rabbit,species:.rabbit,baby:baby), gaze = Rig.gaze(rabbit)!
            let body = bone(rabbit,"body"), bodyRest = body.eulerAngles
            rig.apply(distance:0,phase:0.25/0.75)
            close(bone(rabbit,"backlegs").eulerAngles.x,-125*radians)
            if !baby {
                rig.apply(distance:0,phase:0.2083/0.75)
                close(bone(rabbit,"rightBackLeg").eulerAngles.x,-47.5*radians)
                rig.apply(distance:0,phase:0.25/0.75)
            }
            let animated = head.eulerAngles
            gaze.eulerAngles = .init(0.2,0.3,0)
            rig.apply(distance:0,phase:0.25/0.75)
            close(head.eulerAngles.x,animated.x); close(head.eulerAngles.y,animated.y)
            close(gaze.eulerAngles.x,0.2); close(gaze.eulerAngles.y,0.3)
            rig.idle(); close(body.eulerAngles.x,bodyRest.x)
            precondition(Rig.legs(rabbit).count == 2,"Generic gait must not drive rabbit groups and their children twice")
            let profile = try factory.locomotion(.rabbit,baby:baby).skip!
            close(profile.height,0.25); close(profile.duration,0.9); close(profile.delay,0.75)
        }
        let profile = Rig.Skip(height:0.25,duration:0.9,delay:0.75,distance:0.8)
        let hop = Rig.Hop(start:.init(0,0,0),end:.init(1,0,0),skip:profile)
        close(hop.point(0).x,0); close(hop.point(0).y,0)
        close(hop.point(1).x,1); close(hop.point(1).y,0)
        close(hop.point((1.0/6+8.0/9)/2).y,0.25)
        precondition(!hop.clear {a,b in !(a.x<0.5 && b.x>=0.5)},"Takeoff and landing must sweep through intermediate obstacles")
        precondition(!hop.clear {a,b in max(a.y,b.y)+0.6<0.75},"A low ceiling must reject the full hop")

        let fixture = SCNNode(), root = SCNNode(), child = SCNNode()
        root.name = "body"; root.position = .init(0,10.0/16,2.0/16); fixture.addChildNode(root)
        child.name = "arms"; child.position = .init(0,-2.0/16,0); root.addChildNode(child)
        let definition: [String:Any] = ["bones":[["name":"body","pivot":[0.0,10.0,2.0]],
            ["name":"arms","parent":"body","pivot":[0.0,8.0,2.0]]]]
        let setup: [String:[String:Any]] = ["body":["position":["-this","-14-this","2-this"]],
            "arms":["position":[0,"-3-this","-1-this"]]]
        try Rig.setup(setup,model:fixture,definition:definition)
        close(root.position.y,10.0/16,"Root reset Y uses the native 24px origin")
        close(child.position.y,-3.0/16,"Child reset Y stays parent-local")
        try Rig.setup(setup,model:fixture,definition:definition)
        close(child.position.y,-3.0/16,"Rest application must not accumulate")
        let bound: [String:Any] = ["bones":[["name":"body","pivot":[0.0,10.0,2.0],
            "bind_pose_rotation":[90.0,0.0,0.0],"rotation":[15.0,0.0,0.0]]]]
        try Rig.setup(["body":["rotation":["-this",0,0]]],model:fixture,definition:bound)
        close(root.eulerAngles.x,-Double.pi/2,"Reset animated rotation must retain the bind")
        close(try Rig.scale("query.is_baby ?2.0:1.2",baby:false),1.2)
        close(try Rig.scale("query.is_baby ?2.0:1.2",baby:true),2)
        reject {_ = try Rig.scale("query.unsupported ?1:2",baby:false)}
        reject {try Rig.setup(["body":["position":["query.unrecognised",0,0]]],model:fixture,definition:definition)}
        reject {try Rig.setup(["body":["rotation":[true,0,0]]],model:fixture,definition:definition)}
        reject {_ = try Rig.Channel(["0.0":[0,0,0],"0.5":[true,0,0]],duration:1)}
        let discontinuous = try Rig.Channel(["0.0":[0.0,0.0,0.0],"0.5":["pre":[10.0,0.0,0.0],"post":[20.0,0.0,0.0]],"1.0":[30.0,0.0,0.0]],duration:1)
        close(discontinuous.sample(0.499999).x,9.99998); close(discontinuous.sample(0.5).x,20)
    }
}
